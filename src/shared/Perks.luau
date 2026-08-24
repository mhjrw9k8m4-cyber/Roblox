--!strict
--[[
	Perks — trvalé bonusy kupované za tokeny z rebirthu.

	Proč vůbec: rebirth byl do teď jedno číslo. Zaplatíš, dostaneš
	+50 % ke všemu a jedeš dál. Není v tom žádné rozhodnutí — a to je
	škoda právě u kroku, který hráče stojí celý postup.

	Token za každý rebirth se dá utratit za jednu z několika větví.
	Nejde koupit všechno, takže druhý rebirth vypadá jinak než první
	a hráči si mezi sebou nejsou podobní.

	Modul je čistý: server podle něj ověřuje nákup, Economy podle něj
	počítá bonusy a panel podle něj kreslí strom. Jeden zdroj pravdy.
]]

local Perks = {}

export type Perk = {
	Id: string,
	Name: string,
	Desc: string,
	Icon: string,
	MaxLevel: number,
	-- Kolik tokenů stojí úroveň n (n-tý prvek); poslední platí i dál
	Cost: { number },
	-- O kolik se bonus posune za každou úroveň
	PerLevel: number,
	-- Kolik rebirthů musí hráč mít, než se větev vůbec ukáže
	Requires: number,
}

--[[
	Ceny rostou, ale ne o moc: cílem není další exponenciála, ale to,
	aby si hráč nemohl v desátém rebirthu odemknout úplně všechno.
]]
Perks.List = {
	{
		Id = "Keep",
		Name = "Muscle Memory",
		Desc = "Rebirth ti nechá část úrovní vylepšení",
		Icon = "🧠",
		MaxLevel = 5,
		Cost = { 1, 1, 2, 3, 4 },
		PerLevel = 0.1, -- 10 % úrovní za stupeň, na pátém půlka
		Requires = 0,
	},
	{
		Id = "Offline",
		Name = "Night Shift",
		Desc = "Vyšší výdělek, když nehraješ",
		Icon = "🌙",
		MaxLevel = 5,
		Cost = { 1, 2, 2, 3, 4 },
		PerLevel = 0.25,
		Requires = 0,
	},
	{
		Id = "Slot",
		Name = "Pack Leader",
		Desc = "+1 slot na peta",
		Icon = "🐾",
		MaxLevel = 3,
		Cost = { 2, 4, 7 },
		PerLevel = 1,
		Requires = 1,
	},
	{
		Id = "Combo",
		Name = "Flow State",
		Desc = "Řetěz vydrží déle, než spadne",
		Icon = "🌊",
		MaxLevel = 4,
		Cost = { 1, 2, 3, 5 },
		PerLevel = 0.35, -- sekundy k oknu
		Requires = 1,
	},
	{
		Id = "Overkill",
		Name = "Demolition",
		Desc = "Přeplácnutí zdi platí víc",
		Icon = "💥",
		MaxLevel = 5,
		Cost = { 2, 3, 4, 6, 8 },
		PerLevel = 0.06, -- přičítá se ke křivce přeplácnutí
		Requires = 2,
	},
	{
		Id = "Gem",
		Name = "Prospector",
		Desc = "+1 gem za dokončené kolo světa",
		Icon = "💎",
		MaxLevel = 5,
		Cost = { 2, 3, 4, 5, 6 },
		PerLevel = 1,
		Requires = 3,
	},
	{
		Id = "Luck",
		Name = "Four Leaf",
		Desc = "+2 % šance na ×5 pickup, navrch k vylepšení",
		Icon = "🍀",
		MaxLevel = 5,
		Cost = { 3, 4, 5, 6, 8 },
		PerLevel = 0.02,
		Requires = 4,
	},
	{
		Id = "Rebirth",
		Name = "Compound",
		Desc = "Každý rebirth dá o něco víc než dřív",
		Icon = "⭐",
		MaxLevel = 5,
		Cost = { 4, 6, 8, 11, 15 },
		PerLevel = 0.1, -- přičítá se k BonusPerRebirth
		Requires = 5,
	},
} :: { Perk }

function Perks.get(id: string): Perk?
	for _, perk in Perks.List do
		if perk.Id == id then
			return perk
		end
	end
	return nil
end

function Perks.level(profile: any, id: string): number
	return (profile.Perks and profile.Perks[id]) or 0
end

-- Hodnota bonusu při dané úrovni (0 = větev nekoupená).
function Perks.value(profile: any, id: string): number
	local perk = Perks.get(id)
	if not perk then
		return 0
	end
	return Perks.level(profile, id) * perk.PerLevel
end

--[[
	Cena další úrovně, nebo nil při maximu.

	Seznam cen může být kratší než MaxLevel — poslední uvedená pak
	platí i pro zbylé úrovně. Ušetří to opisování stejného čísla.
]]
function Perks.cost(perk: Perk, level: number): number?
	if level >= perk.MaxLevel then
		return nil
	end
	return perk.Cost[math.min(level + 1, #perk.Cost)]
end

--[[
	Kolik tokenů hráč celkem dostal a kolik jich ještě má.

	Vydané tokeny se neukládají zvlášť — dopočítají se ze zakoupených
	úrovní. Nejde tak rozjet stav, ve kterém profil tvrdí, že tokeny
	má, ale za perky je nikdy nezaplatil.
]]
function Perks.spent(profile: any): number
	local total = 0

	for _, perk in Perks.List do
		local level = Perks.level(profile, perk.Id)
		for step = 0, level - 1 do
			total += perk.Cost[math.min(step + 1, #perk.Cost)]
		end
	end

	return total
end

function Perks.earned(profile: any): number
	return profile.Rebirths or 0
end

function Perks.available(profile: any): number
	return math.max(Perks.earned(profile) - Perks.spent(profile), 0)
end

function Perks.unlocked(profile: any, perk: Perk): boolean
	return (profile.Rebirths or 0) >= perk.Requires
end

--[[
	Smí hráč koupit další úroveň? Vrací i důvod, aby ho UI mohlo
	napsat rovnou na tlačítko místo mlčení.
]]
function Perks.canBuy(profile: any, id: string): (boolean, string?)
	local perk = Perks.get(id)
	if not perk then
		return false, "Unknown perk."
	end
	if not Perks.unlocked(profile, perk) then
		return false, `Needs {perk.Requires} rebirths.`
	end

	local level = Perks.level(profile, id)
	local cost = Perks.cost(perk, level)
	if not cost then
		return false, "Max level."
	end
	if Perks.available(profile) < cost then
		return false, "Not enough tokens."
	end

	return true, nil
end

-- Zapíše koupenou úroveň. Neověřuje — to dělá `canBuy` na serveru.
function Perks.apply(profile: any, id: string)
	profile.Perks = profile.Perks or {}
	profile.Perks[id] = Perks.level(profile, id) + 1
end

return Perks

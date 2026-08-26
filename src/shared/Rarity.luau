--!strict
--[[
	Rarity — jedna stupnice vzácnosti pro celou hru.

	Vzácnost do teď měla jenom kosmetika a byla dopsaná ručně u každého
	kusu. Všechno ostatní — světy, hračky, vylepšení, perky, boosty,
	tituly — bylo "prostě položka v seznamu". Hráč tak neměl jak poznat,
	jestli je věc, na kterou zrovna kouká, začátečnická, nebo jedna
	z posledních ve hře, dokud si neporovnal ceny.

	Přitom je to ta samá informace, jakou nese barevný rámeček v každé
	velké hře žánru: **kam v celé řadě ta věc patří**.

	══ Proč se to počítá a nepíše ručně ══

	Kdyby měl každý svět a každá hračka `Rarity = "Epic"` v datech,
	rozešlo by se to při prvním přidání obsahu: přidáš tři světy na
	konec a "Legendary" najednou sedí uprostřed hry. Pořadí v žebříčku
	je naopak vždycky pravda — a žebříček tu už je, jen se jmenuje cena
	nebo síla.

	Ruční hodnota zůstává jedinému druhu obsahu: kosmetice. Tam totiž
	žádný žebříček není (stopa není "dražší" než jiná stopa) a vzácnost
	je autorské rozhodnutí.
]]

local Rarity = {}

export type Tier = {
	Id: string,
	Name: string,
	Color: Color3,
	Order: number,
}

--[[
	Pět stupňů, ne šest ani deset. Míň by nerozlišilo začátek od konce,
	víc by po hráči chtělo, aby si pamatoval pořadí barev — a to nikdo
	nedělá. Pět je přesně tolik, kolik jich používají hry, ze kterých
	tenhle žánr vyrostl, takže je hráč zná odjinud.
]]
Rarity.List = {
	{ Id = "Common", Name = "COMMON", Color = Color3.fromRGB(186, 196, 214), Order = 1 },
	{ Id = "Rare", Name = "RARE", Color = Color3.fromRGB(96, 226, 255), Order = 2 },
	{ Id = "Epic", Name = "EPIC", Color = Color3.fromRGB(150, 86, 255), Order = 3 },
	{ Id = "Legendary", Name = "LEGENDARY", Color = Color3.fromRGB(255, 196, 60), Order = 4 },
	{ Id = "Mythic", Name = "MYTHIC", Color = Color3.fromRGB(255, 86, 178), Order = 5 },
} :: { Tier }

function Rarity.at(index: number): Tier
	return Rarity.List[math.clamp(math.floor(index), 1, #Rarity.List)]
end

function Rarity.byId(id: string): Tier
	for _, tier in Rarity.List do
		if tier.Id == id then
			return tier
		end
	end
	return Rarity.List[1]
end

--[[
	Kolikátá věc z kolika → stupeň.

	Tohle je celé jádro modulu. Rozdělí žebříček na pět stejných dílů,
	takže první pětina obsahu je běžná a poslední mýtická — ať je toho
	deset kusů nebo sto.

	Pracuje se s pořadím, ne s cenou: ceny v tomhle žánru rostou
	násobky, takže "polovina nejdražší ceny" je ve skutečnosti kousek
	před koncem, ne půlka hry.
]]
function Rarity.byRank(rank: number, total: number): Tier
	if total <= 0 then
		return Rarity.List[1]
	end
	local share = math.clamp(rank, 1, total) / total
	return Rarity.at(math.ceil(share * #Rarity.List))
end

--[[
	Pořadí položky v seřazeném seznamu.

	Řadí se kopie, ne původní tabulka: `Config.Worlds` i `Live.Squishies`
	jsou pořadím obsahu a přeházet je znamená přeházet celou hru.
]]
local function rankOf(list: { any }, id: string, key: string): (number, number)
	local sorted = table.clone(list)
	table.sort(sorted, function(left, right)
		if left[key] == right[key] then
			-- Stabilně podle id, aby dvě stejně drahé věci nepřeskakovaly
			return left.Id < right.Id
		end
		return left[key] < right[key]
	end)

	for index, entry in sorted do
		if entry.Id == id then
			return index, #sorted
		end
	end

	return 1, #sorted
end

function Rarity.byLadder(list: { any }, id: string, key: string): Tier
	local rank, total = rankOf(list, id, key)
	return Rarity.byRank(rank, total)
end

return Rarity

--!strict
--[[
	Patterns — textury vyrobené vzorem, ne obrázkem.

	Nahrát vlastní obrázek nejde: cizí `rbxassetid://` se v jiné hře
	nepřehraje ani nezobrazí, a `EditableImage` je ve vydaných hrách
	vypnutý, dokud si tvůrce neověří věk a totožnost. Textura se tedy
	musí vyrobit z toho, co je k dispozici.

	Populární Roblox hry na to mají odpověď starou jako platforma sama:
	**vzor se skládá z dílů**. Šachovnice, pruhy, posypka — nic z toho
	není obrázek, je to jen chytře obarvená mřížka kostek. Vypadá to
	přesně jako "klasická Roblox grafika", protože to přesně ona je.

	Modul je čistá funkce: ze souřadnic dlaždice vrátí její barvu.
	Nekreslí, nic nevytváří, nesahá na Roblox API — takže se dá
	otestovat a server i klient z něj dostanou totéž.
]]

local Patterns = {}

export type Palette = {
	Base: Color3,
	Accent: Color3,
	-- Třetí odstín pro vzory, které ho potřebují (posypka, mramor)
	Extra: Color3?,
}

--[[
	Deterministické míchání souřadnic.

	Stejné jako u zlatých pickupů a ze stejného důvodu: `math.random`
	by dal každému hráči jiný vzor. Násobitele jsou 16bitové, protože
	Luau počítá v doublech a součin dvou 32bitových čísel by přetekl
	přesnost — spodní bity, na kterých vzor stojí, by se tiše ztratily.
]]
local function mix(x: number, y: number): number
	local n = bit32.band(x * 374761 + y * 668265, 0xFFFFFFFF)

	n = bit32.bxor(n, bit32.rshift(n, 15))
	n = bit32.band(n * 0x9E37, 0xFFFFFFFF)
	n = bit32.bxor(n, bit32.rshift(n, 13))

	return n % 1000 / 1000
end

--[[
	Barva jedné dlaždice.

	`column` a `row` jsou souřadnice v mřížce (celá čísla od nuly).
	Vrací barvu, kterou má ta dlaždice mít.

	Vzory jsou schválně jednoduché. Složitý vzor se z kostek o hraně
	pěti studů stejně nepřečte — na zemi vidíš vždycky jen pár řad
	a rozdíl musí být poznat na první pohled.
]]
function Patterns.tile(kind: string, column: number, row: number, palette: Palette): Color3
	local base = palette.Base
	local accent = palette.Accent
	local extra = palette.Extra or accent

	if kind == "checker" then
		-- Klasika: střídání po jedné. Čte se i za běhu.
		return if (column + row) % 2 == 0 then base else accent
	elseif kind == "stripes" then
		-- Pruhy napříč tratí: podtrhují směr běhu
		return if row % 3 == 0 then accent else base
	elseif kind == "lanes" then
		-- Pruhy PODÉL trati, v místech sloupců s pickupy
		return if column % 3 == 1 then accent else base
	elseif kind == "dots" then
		-- Řídké tečky v pravidelném rastru: klidný podklad
		return if column % 3 == 1 and row % 3 == 1 then accent else base
	elseif kind == "sprinkles" then
		--[[
			Posypka. Náhodně rozházené barevné kousky — jediný vzor,
			který používá míchání, protože pravidelná posypka není posypka.
		]]
		local roll = mix(column, row)
		if roll < 0.1 then
			return accent
		elseif roll < 0.18 then
			return extra
		end
		return base
	elseif kind == "waves" then
		-- Vlna napříč: řada se posouvá podle sinu sloupce
		local shift = math.floor(math.sin(column * 0.9) * 1.5 + 1.5)
		return if (row + shift) % 4 == 0 then accent else base
	elseif kind == "marble" then
		--[[
			Žilkování. Tenká klikatá linka místo plochy — vzniká tím,
			že se bere jen úzké pásmo hodnot kolem prahu.
		]]
		local vein = mix(column, row // 2)
		return if vein > 0.46 and vein < 0.54 then accent else base
	elseif kind == "grid" then
		-- Spáry: mřížka tenkých linek, jinak jednolitá plocha
		return if column % 4 == 0 or row % 4 == 0 then accent else base
	elseif kind == "holes" then
		--[[
			Sýrové díry: shluky, ne rastr. Kolem každého zásahu se
			obarví i sousedi, takže z toho vyjde kulatá skvrna a ne
			jedna osamocená dlaždice.
		]]
		local roll = mix(column // 2, row // 2)
		if roll < 0.12 then
			return accent
		elseif roll < 0.2 then
			return extra
		end
		return base
	elseif kind == "bricks" then
		-- Cihly: každá druhá řada posunutá o půlku, jako zdivo
		local shift = if row % 2 == 0 then 0 else 2
		return if (column + shift) % 4 == 0 or row % 2 == 0 and row % 4 == 0 then accent else base
	elseif kind == "rings" then
		--[[
			Soustředné kruhy od středu trati. Šířka pásu se počítá ze
			vzdálenosti, takže se to nerozjede při jiné šířce chodby.
		]]
		local distance = math.sqrt(column * column + row * row)
		return if math.floor(distance) % 4 == 0 then accent else base
	elseif kind == "crumbs" then
		-- Drobenka: hustší a jemnější než posypka, jen dva odstíny
		local roll = mix(column * 3, row * 3)
		return if roll < 0.28 then accent else base
	end

	return base
end

-- Všechny vzory, které modul umí. Testy podle toho projdou každý.
Patterns.Kinds = {
	"checker", "stripes", "lanes", "dots",
	"sprinkles", "waves", "marble", "grid",
	-- Přibyly, když se z šesti zón staly dvanáct levelů: každý level
	-- má mít vlastní kresbu, jinak si dva začnou být podobné
	"holes", "bricks", "rings", "crumbs",
}

function Patterns.has(kind: string): boolean
	return table.find(Patterns.Kinds, kind) ~= nil
end

--[[
	Kolik z plochy vzor obarví akcentem.

	Používá se v testech: vzor, který obarví skoro všechno nebo skoro
	nic, není vzor — je to jednolitá plocha a v mřížce se ztratí.

	Vzorkuje se 64×64, ne menší plocha. Krátké okno totiž měření
	zkresluje směrem NAHORU: vzor s periodou 40 trefí v okně 24 řad
	právě jednu a vyjde z něj 4 % místo skutečných 2,5 %. Test by pak
	takový vzor pustil, i když je ve hře prakticky neviditelný — na to
	jsem narazil při ověřování, že ten test vůbec umí selhat.
]]
function Patterns.coverage(kind: string, palette: Palette): number
	local hits = 0
	local total = 0

	for column = 0, 63 do
		for row = 0, 63 do
			total += 1
			if Patterns.tile(kind, column, row, palette) ~= palette.Base then
				hits += 1
			end
		end
	end

	return hits / total
end

return Patterns

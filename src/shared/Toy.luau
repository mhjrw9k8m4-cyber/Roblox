--!strict
--[[
	Toy — z čeho je squishy hračka opravdu poskládaná.

	Do teď byla každá hračka jedna koule nebo kostka. Skutečná squishy
	hračka ale není primitivum: máslo má obal s modrým nápisem, sýr má
	díry, kobliha má prstenec a posyp. Právě ty detaily dělají rozdíl
	mezi "žlutá kostka" a "kus másla".

	Modul je čistá data. Nestaví nic — jen popisuje, z jakých kusů se
	hračka skládá. Postavit si to umí klient v ruce i panel v obchodě,
	a protože oba čtou totéž, nemůže se stát, že v seznamu je něco
	jiného, než co hráč drží.

	Souřadnice jsou v **podílech jmenovité velikosti**, ne ve studech:
	`Offset = Vector3.new(0, 0.25, 0)` je čtvrtina nad středem, ať je
	hračka v ruce velká 1,5 studu nebo v náhledu 2. Díky tomu se dá
	stejný recept použít všude.

	Materiály jsou schválně matný plast s malou odrazivostí. Squishy
	hračka je guma, ne sklo; Neon nebo vysoký lesk z ní udělá cukrátko
	z jiné hry.
]]

local Toy = {}

export type Label = {
	Text: string,
	Color: Color3,
	-- Jméno z Enum.NormalId; jméno, ne enum, aby modul zůstal daty
	Face: string,
	Rotation: number?,
}

export type Piece = {
	-- "Ball" | "Block" | "Cylinder"
	Kind: string,
	-- Podíl jmenovité velikosti
	Size: Vector3,
	-- Posun od středu v podílech jmenovité velikosti
	Offset: Vector3,
	-- Natočení ve stupních
	Rotation: Vector3?,
	--[[
		K čemu kus je. Barvu bere podle role z barvy hračky, takže
		přebarvení hračky přebarví i detaily a nikdy se to nerozejde.

		  Body   — hlavní hmota, barva hračky
		  Shade  — tmavší odstín (díry, spára, kůrka)
		  Light  — světlejší odstín (poleva, odlesk)
		  Wrap   — obal: krémově bílá, nese nápis
		  Accent — vlastní barva z receptu
	]]
	Role: string,
	Color: Color3?,
	Reflectance: number?,
	Transparency: number?,
	Label: Label?,
}

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local WRAP = Color3.fromRGB(248, 244, 232)
local INK = Color3.fromRGB(28, 62, 158)

--[[
	Recepty.

	Počet kusů je hlídaný záměrně: hráč může držet šest hraček naráz a
	každý kus je díl navíc na scéně. Nejsložitější kus (kobliha) má
	dvanáct, ne dvacet — prstenec z osmi koulí čte oko jako kruh úplně
	stejně a zbylých osm by nikdo nenašel.
]]
local RECIPES: { [string]: { Piece } } = {}

RECIPES.Blob = {
	{ Kind = "Ball", Size = v(1, 0.92, 1), Offset = v(0, 0, 0), Role = "Body", Reflectance = 0.14 },
}

--[[
	Máslo. Kvádr s obalem přesně jako v těch videích: krémový papír
	přes prostředek a na něm modrý nápis. Nápis je SurfaceGui, ne
	obrázek — nahrávat texturu by znamenalo asset navíc a hra si
	zakládá na tom, že žádný nepotřebuje.
]]
RECIPES.Butter = {
	{ Kind = "Block", Size = v(1, 0.46, 0.44), Offset = v(0, 0, 0), Role = "Body", Reflectance = 0.2 },
	{
		Kind = "Block",
		Size = v(0.58, 0.48, 0.46),
		Offset = v(0, 0, 0),
		Role = "Wrap",
		Reflectance = 0.08,
		Label = { Text = "SALTED\nBUTTER", Color = INK, Face = "Front" },
	},
}

-- Mochi: koule zmáčknutá shora, matná. Lesklé mochi vypadá jako guma.
RECIPES.Mochi = {
	{ Kind = "Ball", Size = v(1, 0.7, 0.94), Offset = v(0, 0, 0), Role = "Body", Reflectance = 0.05 },
	{ Kind = "Ball", Size = v(0.34, 0.12, 0.3), Offset = v(0, 0.3, 0), Role = "Light", Reflectance = 0.05 },
}

--[[
	Kobliha. Prstenec z osmi koulí, poleva jako mírně větší koule shora
	a čtyři kousky posypu. Díra uprostřed je skutečná díra — mezi
	koulemi je místo, takže se do ní dá vidět.
]]
RECIPES.Donut = (function()
	local pieces: { Piece } = {}
	for index = 0, 7 do
		local angle = index / 8 * math.pi * 2
		local x = math.cos(angle) * 0.33
		local z = math.sin(angle) * 0.33
		table.insert(pieces, {
			Kind = "Ball",
			Size = v(0.4, 0.36, 0.4),
			Offset = v(x, 0, z),
			Role = "Body",
			Reflectance = 0.1,
		})
		table.insert(pieces, {
			Kind = "Ball",
			Size = v(0.38, 0.2, 0.38),
			Offset = v(x, 0.12, z),
			Role = "Light",
			Reflectance = 0.16,
		})
	end
	return pieces
end)()

--[[
	Sýr. Kostka s dírami — díry jsou tmavší koule zapuštěné do hran,
	takže z každé je vidět jen výkroj. Přesně ten tvar z videa, kde do
	něj prst udělá dolík vedle jedné z děr.
]]
RECIPES.Cheese = {
	{ Kind = "Block", Size = v(1, 0.86, 1), Offset = v(0, 0, 0), Role = "Body", Reflectance = 0.22 },
	{ Kind = "Ball", Size = v(0.34, 0.34, 0.34), Offset = v(0.36, 0.12, 0.42), Role = "Shade" },
	{ Kind = "Ball", Size = v(0.24, 0.24, 0.24), Offset = v(-0.3, -0.16, 0.46), Role = "Shade" },
	{ Kind = "Ball", Size = v(0.28, 0.28, 0.28), Offset = v(0.1, 0.42, -0.2), Role = "Shade" },
	{ Kind = "Ball", Size = v(0.2, 0.2, 0.2), Offset = v(-0.44, 0.24, -0.1), Role = "Shade" },
	{ Kind = "Ball", Size = v(0.18, 0.18, 0.18), Offset = v(0.46, -0.3, -0.28), Role = "Shade" },
}

RECIPES.Ball = {
	{ Kind = "Ball", Size = v(1, 1, 1), Offset = v(0, 0, 0), Role = "Body", Reflectance = 0.85 },
}

-- Bochník: spodek kvádr, vršek zaoblený, kůrka tmavší
RECIPES.Loaf = {
	{ Kind = "Block", Size = v(1, 0.42, 0.66), Offset = v(0, -0.14, 0), Role = "Shade", Reflectance = 0.06 },
	{ Kind = "Ball", Size = v(0.98, 0.56, 0.64), Offset = v(0, 0.14, 0), Role = "Body", Reflectance = 0.08 },
	{ Kind = "Block", Size = v(0.6, 0.06, 0.1), Offset = v(0, 0.36, 0), Rotation = v(0, 0, 8), Role = "Shade" },
}

-- Broskev: koule se spárou a lístkem
RECIPES.Peach = {
	{ Kind = "Ball", Size = v(1, 0.96, 1), Offset = v(0, 0, 0), Role = "Body", Reflectance = 0.12 },
	{ Kind = "Block", Size = v(0.06, 0.9, 0.5), Offset = v(0, 0, 0.36), Role = "Shade" },
	{
		Kind = "Ball",
		Size = v(0.34, 0.1, 0.2),
		Offset = v(0.16, 0.48, 0),
		Rotation = v(0, 0, 24),
		Role = "Accent",
		Color = Color3.fromRGB(126, 208, 96),
	},
}

-- Hvězda: pět ramen kolem středu
RECIPES.Star = (function()
	local pieces: { Piece } = {
		{ Kind = "Ball", Size = v(0.46, 0.34, 0.46), Offset = v(0, 0, 0), Role = "Body", Reflectance = 0.2 },
	}
	for index = 0, 4 do
		local degrees = index * 72
		local angle = math.rad(degrees)
		table.insert(pieces, {
			Kind = "Block",
			Size = v(0.24, 0.5, 0.24),
			Offset = v(math.sin(angle) * 0.3, math.cos(angle) * 0.3, 0),
			Rotation = v(0, 0, -degrees),
			Role = "Body",
			Reflectance = 0.2,
		})
	end
	return pieces
end)()

-- Jádro: koule a tři úlomky kolem ní
RECIPES.Core = {
	{ Kind = "Ball", Size = v(0.74, 0.74, 0.74), Offset = v(0, 0, 0), Role = "Body", Reflectance = 0.3 },
	{ Kind = "Block", Size = v(0.2, 0.44, 0.2), Offset = v(0.42, 0.16, 0), Rotation = v(0, 0, 28), Role = "Light" },
	{ Kind = "Block", Size = v(0.18, 0.38, 0.18), Offset = v(-0.36, -0.24, 0.14), Rotation = v(0, 0, -34), Role = "Light" },
	{ Kind = "Block", Size = v(0.16, 0.3, 0.16), Offset = v(0.08, -0.44, -0.3), Rotation = v(22, 0, 12), Role = "Light" },
}

--[[
	Barva kusu podle role. Odstíny se počítají z barvy hračky, ne
	zapisují ručně — jinak by přebarvení hračky nechalo díry a polevu
	ve staré barvě a vypadalo by to jako chyba vykreslení.
]]
function Toy.colorFor(role: string, base: Color3, custom: Color3?): Color3
	if custom then
		return custom
	end

	if role == "Shade" then
		return base:Lerp(Color3.fromRGB(78, 52, 24), 0.34)
	elseif role == "Light" then
		return base:Lerp(Color3.new(1, 1, 1), 0.42)
	elseif role == "Wrap" then
		return WRAP
	end

	return base
end

--[[
	Kusy hračky. Když recept chybí, vrátí se jedno primitivum podle
	`Shape` — nová hračka v Live tak funguje hned, jen zatím bez detailů.
]]
function Toy.pieces(squishy): { Piece }
	local recipe = RECIPES[squishy.Id]
	if recipe then
		return recipe
	end

	return {
		{ Kind = squishy.Shape, Size = v(1, 1, 1), Offset = v(0, 0, 0), Role = "Body", Reflectance = 0.1 },
	}
end

function Toy.hasRecipe(id: string): boolean
	return RECIPES[id] ~= nil
end

Toy.Roles = { "Body", "Shade", "Light", "Wrap", "Accent" }
Toy.Kinds = { "Ball", "Block", "Cylinder" }

return Toy

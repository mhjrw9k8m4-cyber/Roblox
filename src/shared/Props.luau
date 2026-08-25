--!strict
--[[
	Props — rekvizity, které dělají ze světa místo.

	Šest světů se do teď lišilo jen barvou a materiálem. Chodba byla
	pořád stejná chodba, takže "Ledová klenba" a "Čokoládovna" byly
	dvě jména pro totéž.

	Tenhle modul je popis toho, co v každém světě stojí kolem trati.
	Je to **jen data**: seznam kusů, jejich rozměry, posuny a natočení.
	Nic se tu nekreslí a nesahá se na Roblox API, takže se dá celý
	otestovat — a přidat svět znamená přidat tabulku, ne psát kód.

	Rekvizita se skládá z kusů, protože Roblox umí jen několik tvarů
	(kvádr, koule, válec, klín). Kužel se musí poskládat ze tří válců,
	prstenec z osmi kvádrů dokola. Právě z toho vzniká ten "stavebnicový"
	vzhled, kterým jsou populární Roblox hry poznat.

	Barvy se neuvádějí přímo, ale jménem role (`World`, `Accent`,
	`Dark`, `Light`). Svět si je dosadí sám, takže jedna rekvizita
	může posloužit víc světům a nikde se neopisuje hex.
]]

local Props = {}

export type Piece = {
	Shape: string, -- "Block" | "Ball" | "Cylinder" | "Wedge"
	Offset: Vector3,
	Size: Vector3,
	-- Role barvy: World, Accent, Dark, Light
	Color: string,
	Material: string,
	-- Natočení ve stupních
	Rotation: Vector3?,
	Transparency: number?,
	-- Jas světla; nil = díl nesvítí
	Glow: number?,
}

export type Prop = {
	Id: string,
	Pieces: { Piece },
	-- "both" | "left" | "right" | "center"
	Side: string,
	-- Po kolika úsecích se opakuje
	Every: number,
	-- Vzdálenost od osy trati (u "center" se ignoruje)
	Distance: number,
	Height: number,
	--[[
		Když je vyplněné, rekvizita se vznáší a otáčí. Číslo je rychlost;
		klient si takové díly posbírá podle atributu a animuje je
		v jedné smyčce (viz `Textures`).
	]]
	Float: number?,
}

local function piece(
	shape: string,
	offset: Vector3,
	size: Vector3,
	color: string,
	material: string,
	extra: { Rotation: Vector3?, Transparency: number?, Glow: number? }?
): Piece
	local options = extra or {}
	return {
		Shape = shape,
		Offset = offset,
		Size = size,
		Color = color,
		Material = material,
		Rotation = options.Rotation,
		Transparency = options.Transparency,
		Glow = options.Glow,
	}
end

local V = Vector3.new

--[[
	Cukrovinky — rekvizity, které se poznají na první pohled.

	Zbytek modulu jsou tvary: krystal, střep, monolit, trhlina. Fungují
	jako výplň, ale na screenshotu z velké hry v žánru stojí kolem trati
	**věci, které člověk zná** — cukrová hůl, sušenka, jahoda, koktejl.
	Rozdíl mezi "abstraktní modrý útvar" a "jahoda" je přesně ten rozdíl
	mezi kulisou a světem.

	Poznatelnost stojí na siluetě, ne na detailu. Hůl musí mít hák,
	koktejl brčko, jahoda lístky. Pruhy na holi jsou proto samostatné
	kusy, i když by šly nahradit texturou: silueta z dálky rozhoduje,
	povrch až zblízka.

	Barvy se u nich uvádějí rolí jako u všech ostatních, takže sušenka
	v čokoládovém světě zhnědne a ve skle zesvětlá, aniž by se cokoliv
	opisovalo.
]]
local function candyCane(distance: number, every: number): Prop
	local pieces: { Piece } = {
		piece("Cylinder", V(0, 9, 0), V(18, 2.6, 2.6), "Light", "SmoothPlastic", {
			Rotation = V(0, 0, 90),
		}),
	}

	--[[
		Hák nahoře: čtyři válce po třiceti stupních. Míň jich vypadá
		jako zalomená trubka, víc už nikdo nepozná.
	]]
	for index = 0, 3 do
		local angle = math.rad(index * 30)
		pieces[#pieces + 1] = piece(
			"Cylinder",
			V(math.sin(angle) * 4, 14 + math.cos(angle) * 4, 0),
			V(4.4, 2.6, 2.6),
			"Light",
			"SmoothPlastic",
			{ Rotation = V(0, 0, 90 - index * 30) }
		)
	end

	-- Červené pruhy; bez nich je to bílá tyč
	for index = 0, 3 do
		pieces[#pieces + 1] = piece(
			"Cylinder",
			V(0, 2 + index * 4, 0),
			V(1.8, 2.8, 2.8),
			"Accent",
			"SmoothPlastic",
			{ Rotation = V(0, 0, 90) }
		)
	end

	return {
		Id = "Cukrová hůl",
		Side = "both",
		Every = every,
		Distance = distance,
		Height = 0,
		Pieces = pieces,
	}
end

local function cookie(distance: number, every: number, height: number): Prop
	local pieces: { Piece } = {
		piece("Cylinder", V(0, 0, 0), V(1.8, 13, 13), "Dark", "SmoothPlastic", {
			Rotation = V(0, 0, 90),
		}),
	}

	--[[
		Kousky čokolády rozmístěné do kruhu, ne náhodně: pravidelná
		sušenka vypadá jako sušenka, náhodná jako skvrna.
	]]
	local spots = { V(3, 3, 1.2), V(-3.4, 2, 1.2), V(1, -3.6, 1.2), V(-2, -2, 1.2), V(4, -1, 1.2) }
	for _, spot in spots do
		pieces[#pieces + 1] = piece("Block", spot, V(2.2, 2.2, 1.4), "Accent", "SmoothPlastic", {
			Rotation = V(0, 0, 24),
		})
	end

	return {
		Id = "Sušenka",
		Side = "both",
		Every = every,
		Distance = distance,
		Height = height,
		Pieces = pieces,
		Float = 0.5,
	}
end

local function strawberry(distance: number, every: number): Prop
	return {
		Id = "Jahoda",
		Side = "both",
		Every = every,
		Distance = distance,
		Height = 0,
		Pieces = {
			piece("Ball", V(0, 6, 0), V(11, 11, 11), "Accent", "SmoothPlastic"),
			-- Špička dolů: koule sama o sobě je míč, ne jahoda
			piece("Ball", V(0, 1.5, 0), V(7, 8, 7), "Accent", "SmoothPlastic"),
			piece("Ball", V(0, -1.5, 0), V(3.4, 4, 3.4), "Accent", "SmoothPlastic"),
			piece("Block", V(2.6, 11.4, 0), V(5, 0.8, 2.4), "Light", "Grass", { Rotation = V(0, 0, 16) }),
			piece("Block", V(-2.6, 11.4, 0), V(5, 0.8, 2.4), "Light", "Grass", { Rotation = V(0, 0, -16) }),
			piece("Block", V(0, 11.4, 2.6), V(2.4, 0.8, 5), "Light", "Grass", { Rotation = V(-16, 0, 0) }),
			piece("Cylinder", V(0, 13, 0), V(2.6, 1, 1), "Dark", "Grass", { Rotation = V(0, 0, 90) }),
		},
	}
end

local function milkshake(distance: number, every: number): Prop
	return {
		Id = "Koktejl",
		Side = "both",
		Every = every,
		Distance = distance,
		Height = 0,
		Pieces = {
			-- Kelímek se zužuje dolů: dva válce nad sebou stačí
			piece("Cylinder", V(0, 5, 0), V(10, 8, 8), "Light", "SmoothPlastic", { Rotation = V(0, 0, 90) }),
			piece("Cylinder", V(0, 12, 0), V(4, 9.6, 9.6), "World", "SmoothPlastic", { Rotation = V(0, 0, 90) }),
			piece("Ball", V(0, 15, 0), V(9, 7, 9), "Light", "SmoothPlastic"),
			piece("Ball", V(0, 18, 0), V(5.4, 4.4, 5.4), "Light", "SmoothPlastic"),
			piece("Ball", V(0, 21, 0), V(3, 3, 3), "Accent", "SmoothPlastic", { Glow = 0.8 }),
			-- Brčko šikmo; svisle vypadá jako anténa
			piece("Cylinder", V(3, 19, 0), V(14, 1.2, 1.2), "Accent", "SmoothPlastic", {
				Rotation = V(0, 0, 68),
			}),
		},
	}
end

local function cone(distance: number, every: number): Prop
	local pieces: { Piece } = {}

	-- Kornout: tři válce, každý užší a níž
	local widths = { 7, 5, 3 }
	for index, width in widths do
		pieces[#pieces + 1] = piece(
			"Cylinder",
			V(0, 6 - (index - 1) * 2.4, 0),
			V(2.6, width, width),
			"Dark",
			"Sand",
			{ Rotation = V(0, 0, 90) }
		)
	end

	pieces[#pieces + 1] = piece("Ball", V(0, 10, 0), V(9, 9, 9), "World", "SmoothPlastic")
	pieces[#pieces + 1] = piece("Ball", V(2, 14, 0), V(6, 6, 6), "Accent", "SmoothPlastic")
	pieces[#pieces + 1] = piece("Ball", V(-2, 14.5, 0), V(5, 5, 5), "Light", "SmoothPlastic")

	return {
		Id = "Kornout",
		Side = "both",
		Every = every,
		Distance = distance,
		Height = 0,
		Pieces = pieces,
	}
end

--[[
	Sklo — krystalická klenba.

	Ostré, nakloněné, průsvitné. Nic tu nestojí rovně: krystal, který
	roste kolmo vzhůru, vypadá jako sloup, ne jako krystal.
]]
local GLASS: { Prop } = {
	{
		Id = "Krystal",
		Side = "both",
		Every = 1,
		Distance = 30,
		Height = 0,
		Pieces = {
			piece("Block", V(0, 7, 0), V(3, 14, 3), "World", "Glass", {
				Rotation = V(12, 20, -8),
				Transparency = 0.35,
			}),
			piece("Block", V(2.5, 4, 1), V(2, 9, 2), "Accent", "Glass", {
				Rotation = V(-14, -25, 16),
				Transparency = 0.3,
				Glow = 1.4,
			}),
			piece("Block", V(-2, 3, -1.5), V(1.6, 6.5, 1.6), "Light", "Glass", {
				Rotation = V(20, 40, 10),
				Transparency = 0.45,
			}),
		},
	},
	{
		Id = "Střep",
		Side = "both",
		Every = 2,
		Distance = 40,
		Height = 22,
		Float = 0.5,
		Pieces = {
			piece("Block", V(0, 0, 0), V(4, 7, 4), "Accent", "Glass", {
				Rotation = V(30, 45, 15),
				Transparency = 0.42,
				Glow = 1.1,
			}),
		},
	},
	candyCane(56, 3),
	cookie(72, 4, 20),
}

--[[
	Želé — kapky a laloky.

	Všechno je kulaté a přetéká. Klíč je, že kapka visí ze stropu
	a pod ní je louže: oko tím dostane příběh, ne jen tvar.
]]
local JELLY: { Prop } = {
	{
		Id = "Lalok",
		Side = "both",
		Every = 1,
		Distance = 27,
		Height = 0,
		Pieces = {
			piece("Ball", V(0, 3, 0), V(11, 6, 11), "World", "Glass", { Transparency = 0.25 }),
			piece("Ball", V(2, 6, -1), V(6, 4.5, 6), "Accent", "Glass", { Transparency = 0.2 }),
			piece("Ball", V(-3, 4.5, 1.5), V(4.5, 3.5, 4.5), "Light", "Glass", { Transparency = 0.3 }),
		},
	},
	{
		Id = "Kapka",
		Side = "both",
		Every = 2,
		Distance = 18,
		Height = 30,
		Pieces = {
			piece("Cylinder", V(0, 0, 0), V(5, 1.6, 1.6), "World", "Glass", {
				Rotation = V(0, 0, 90),
				Transparency = 0.2,
			}),
			piece("Ball", V(0, -3.2, 0), V(2.6, 3.4, 2.6), "Accent", "Glass", {
				Transparency = 0.15,
				Glow = 0.8,
			}),
		},
	},
	strawberry(56, 2),
	milkshake(74, 4),
}

--[[
	Led — rampouchy a kry.

	Kužel Roblox nemá, takže rampouch je stoh tří válců, které se
	zužují. Právě tenhle "poskládaný" tvar je pro platformu typický.
]]
local ICE: { Prop } = {
	{
		Id = "Rampouch",
		Side = "both",
		Every = 1,
		Distance = 22,
		Height = 30,
		Pieces = {
			piece("Cylinder", V(0, 0, 0), V(4, 3.2, 3.2), "Light", "Ice", { Rotation = V(0, 0, 90) }),
			piece("Cylinder", V(0, -3.6, 0), V(4, 2.1, 2.1), "World", "Ice", { Rotation = V(0, 0, 90) }),
			piece("Cylinder", V(0, -6.6, 0), V(3.4, 1, 1), "Accent", "Ice", {
				Rotation = V(0, 0, 90),
				Glow = 0.9,
			}),
		},
	},
	{
		Id = "Kra",
		Side = "both",
		Every = 1,
		Distance = 33,
		Height = 0,
		Pieces = {
			piece("Block", V(0, 5, 0), V(10, 10, 10), "World", "Ice", {
				Rotation = V(8, 22, 5),
				Transparency = 0.15,
			}),
			piece("Block", V(4, 11, 2), V(5, 5, 5), "Light", "Ice", { Rotation = V(-12, 40, 14) }),
		},
	},
	cone(58, 3),
	candyCane(76, 4),
}

--[[
	Čokoláda — kádě a potrubí.

	Jediný svět, který má vypadat jako **provoz**: velké nádoby dole,
	trubky nahoře. Vodorovná trubka přes trať navíc dělá strop tam,
	kde jinde není nic.
]]
local CHOCOLATE: { Prop } = {
	{
		Id = "Káď",
		Side = "both",
		Every = 2,
		Distance = 32,
		Height = 0,
		Pieces = {
			piece("Cylinder", V(0, 6, 0), V(12, 14, 14), "Dark", "Metal", { Rotation = V(0, 0, 90) }),
			piece("Cylinder", V(0, 13.2, 0), V(1.6, 15.4, 15.4), "Accent", "Metal", { Rotation = V(0, 0, 90) }),
			piece("Cylinder", V(0, 12.6, 0), V(0.8, 13, 13), "World", "Glass", {
				Rotation = V(0, 0, 90),
				Glow = 0.7,
			}),
		},
	},
	{
		Id = "Potrubí",
		Side = "center",
		Every = 2,
		Distance = 0,
		Height = 34,
		Pieces = {
			piece("Cylinder", V(0, 0, 0), V(70, 3.4, 3.4), "Dark", "Metal", { Rotation = V(0, 0, 0) }),
			piece("Cylinder", V(0, 0, 0), V(72, 4.4, 4.4), "Accent", "Metal", {
				Rotation = V(0, 0, 0),
				Transparency = 0.6,
			}),
		},
	},
	{
		Id = "Tabulka",
		Side = "both",
		Every = 1,
		Distance = 25,
		Height = 0,
		Pieces = {
			piece("Block", V(0, 1, 0), V(9, 2, 6), "World", "SmoothPlastic", { Rotation = V(0, 12, 0) }),
			piece("Block", V(1.5, 3, 1), V(8, 2, 5.4), "Dark", "SmoothPlastic", { Rotation = V(0, -8, 3) }),
		},
	},
	cookie(56, 2, 16),
	cone(76, 3),
}

--[[
	Neon — kruhy a reklamy.

	Prstenec se skládá z osmi kvádrů dokola. Je to víc dílů než by
	člověk čekal, ale svítící kruh nad tratí je nejvýraznější věc,
	kterou svět má.
]]
local function neonRing(radius: number, thickness: number): { Piece }
	local pieces = {}

	for index = 0, 7 do
		local angle = index / 8 * math.pi * 2
		table.insert(
			pieces,
			piece(
				"Block",
				V(math.cos(angle) * radius, math.sin(angle) * radius, 0),
				V(thickness, radius * 0.9, thickness),
				if index % 2 == 0 then "Accent" else "World",
				"Neon",
				{ Rotation = V(0, 0, -math.deg(angle)), Glow = 1.2 }
			)
		)
	end

	return pieces
end

local NEON: { Prop } = {
	{
		Id = "Prstenec",
		Side = "center",
		Every = 1,
		Distance = 0,
		--[[
			Výška musí být větší než poloměr, jinak spodek prstence
			sahá pod hlavu a hráč jím prochází skrz nohy. Osmnáct to
			nesplňovalo a nebylo to na datech vidět — našel to až test,
			který počítá skutečnou spodní hranu z rozměrů a natočení.
		]]
		Height = 34,
		Float = 0.25,
		Pieces = neonRing(15, 1.6),
	},
	{
		Id = "Reklama",
		Side = "both",
		Every = 2,
		Distance = 26,
		Height = 0,
		Pieces = {
			piece("Block", V(0, 9, 0), V(1.4, 18, 1.4), "Dark", "Metal"),
			piece("Block", V(0, 17, 0), V(10, 6, 0.8), "World", "Neon", { Glow = 1.6 }),
			piece("Block", V(0, 17, 0.6), V(8.6, 4.6, 0.4), "Accent", "Neon", { Glow = 1.2 }),
		},
	},
	milkshake(58, 3),
	strawberry(76, 4),
}

--[[
	Void — monolity a trhliny.

	Nejprázdnější svět ze všech, a to schválně. Málo věcí, ale velkých
	a temných: to je jediný způsob, jak "prázdno" ukázat, aniž by
	chodba vypadala nedodělaně.
]]
local VOID: { Prop } = {
	{
		Id = "Monolit",
		Side = "both",
		Every = 2,
		Distance = 34,
		Height = 0,
		Pieces = {
			piece("Block", V(0, 16, 0), V(6, 32, 6), "Dark", "Slate", { Rotation = V(0, 18, 3) }),
			piece("Block", V(0, 16, 3.2), V(1.2, 26, 0.6), "Accent", "Neon", {
				Rotation = V(0, 18, 3),
				Glow = 1.8,
			}),
		},
	},
	{
		Id = "Úlomek",
		Side = "both",
		Every = 1,
		Distance = 26,
		Height = 14,
		Float = 0.4,
		Pieces = {
			piece("Block", V(0, 0, 0), V(4, 4, 4), "Dark", "Slate", {
				Rotation = V(35, 25, 15),
			}),
			piece("Block", V(0, 0, 0), V(4.6, 4.6, 4.6), "Accent", "ForceField", {
				Rotation = V(35, 25, 15),
				Transparency = 0.5,
				Glow = 0.9,
			}),
		},
	},
	{
		Id = "Pilíř",
		Side = "both",
		Every = 3,
		Distance = 46,
		Height = 0,
		Pieces = {
			piece("Cylinder", V(0, 22, 0), V(44, 7, 7), "Dark", "Slate", {
				Rotation = V(0, 0, 90),
			}),
			piece("Cylinder", V(0, 44, 0), V(3, 9, 9), "Accent", "Neon", {
				Rotation = V(0, 0, 90),
				Glow = 2.2,
			}),
		},
	},
	{
		Id = "Trhlina",
		Side = "center",
		Every = 3,
		Distance = 0,
		Height = 26,
		Float = 0.15,
		Pieces = {
			piece("Block", V(0, 0, 0), V(1.2, 22, 0.4), "Accent", "Neon", {
				Rotation = V(0, 0, 14),
				Glow = 2,
			}),
			piece("Block", V(3, 2, 0), V(0.8, 14, 0.4), "World", "Neon", {
				Rotation = V(0, 0, -22),
				Glow = 1.4,
			}),
			piece("Block", V(-3.4, -1, 0), V(0.7, 11, 0.4), "World", "Neon", {
				Rotation = V(0, 0, 28),
				Glow = 1.2,
			}),
		},
	},
	candyCane(60, 4),
	milkshake(80, 5),
}

Props.World = {
	Glass = GLASS,
	Jelly = JELLY,
	Ice = ICE,
	Chocolate = CHOCOLATE,
	Neon = NEON,
	Void = VOID,
}

-- Rekvizity světa; neznámý svět dostane prázdný seznam, ne chybu.
function Props.forWorld(worldId: string): { Prop }
	return Props.World[worldId] or {}
end

-- Strany, na kterých rekvizita stojí. Prázdné pro "center".
function Props.sides(prop: Prop): { number }
	if prop.Side == "left" then
		return { -1 }
	elseif prop.Side == "right" then
		return { 1 }
	elseif prop.Side == "center" then
		return { 0 }
	end
	return { -1, 1 }
end

return Props

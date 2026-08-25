--!strict
--[[
	Zones — levely trati. Jeden level na jednu zeď.

	Dřív měl celý svět jeden materiál a jednu barvu: hráč proběhl dvanáct
	zdí a pod nohama měl pořád totéž. Postup byl jen v číslech.

	Teď je **každá zeď vstup do jiného levelu** a každý level je ušitý
	podle jedné squishy hračky: máslový, mochi, koblihový, sýrový. Prorazíš
	zeď a jsi jinde — jiná podlaha, jiný strop, jiné stěny, jiný zvuk pod
	nohama a jiná drobnost na trati.

	To spojení s hračkami není náhoda. Hráč drží v ruce máslo a za chvíli
	běží máslovým levelem; to samé, co mačká, se kolem něj rozprostírá do
	celého světa. Level a hračka mají proto společné `Toy`, aby se barvy
	nedaly rozejít.

	Zóna se určuje z indexu bariéry, ne z pozice: server ověřuje průraz
	podle indexu, takže z něj musí vycházet i všechno ostatní.

	Zvuk kroku je jen výška vzorku, ne nová nahrávka — stejný trik jako
	u zbytku hry. Vyšší tón zní tvrději, nižší měkčeji, a mezi levely je
	to slyšet okamžitě.
]]

local Config = require(script.Parent.Config)

local Zones = {}

export type Zone = {
	Id: string,
	Name: string,
	-- Od které bariéry level platí (včetně)
	From: number,
	--[[
		Hračka, podle které je level ušitý. Má ji **každý** level a
		pořadí levelů je zároveň pořadím žebříčku hraček: v levelu, kde
		stojí obří máslo, se máslo taky prodává a stojí přesně tolik,
		kolik si tam hráč může dovolit.

		Dřív to tak nebylo — tři levely hračku neměly a u zbylých bylo
		pořadí náhodné (nejdražší hračka ve hře stála v sedmém levelu,
		desetkrát levnější v devátém). "Kam až jsem došel" pak neneslo
		žádnou informaci o tom, co si hráč může koupit.
	]]
	Toy: string,
	Floor: Color3,
	--[[
		Světlý lem a svit: neonové pásy u paty stěny, rámy desek, obruby
		cedulí. Je světlejší než podlaha schválně — má svítit.
	]]
	Edge: Color3,
	--[[
		Druhá barva **kresby podlahy**.

		Dřív se na kresbu bral `Edge`, jenže ten je světlý a od podlahy
		se skoro nelišil: devět levelů z dvanácti mělo odstup pod 0,45
		a podlaha se z výšky očí slila v jednu plochu. Jednotlivé
		dlaždice byly vidět jen podle spár, ne podle barvy — a přesně
		tím se hra lišila od velkých her v žánru, kde je podlaha vidět
		jako řada samostatných kusů.

		Musí to být proto **tmavší** odstín téhož tónu, ne světlejší.
	]]
	Tile: Color3,
	-- Strop a žebra nad hlavou; bez vlastní barvy by level končil ve výšce očí
	Ceiling: Color3,
	-- Jméno z Enum.Material, ne samotný enum: modul čte i server
	Material: string,
	-- Materiál zdi v tomhle levelu; často jiný než podlaha
	WallMaterial: string,
	-- Klíč do Assets.Terrain — vlastní recept kroku i průrazu
	Sound: string,
	--[[
		Vzor podlahy (viz `Shared.Patterns`). Level se tím liší nejen
		barvou, ale i **kresbou** — a to je rozdíl, který je vidět
		i na dálku, kdežto dva odstíny téže barvy splynou.
	]]
	Pattern: string,
	--[[
		Co je na povrchu navíc: díry v sýru, posyp na koblize, papír na
		másle. Tohle je ta vrstva, která z barevné chodby dělá kus hmoty.
		Staví to `WorldService`, popisuje to `Zones.decor`.
	]]
	Decor: string,
	Reflectance: number,
	Transparency: number,
	-- Jak moc má povrch "měkký" tvar: vyšší = zaoblenější lem
	Squish: number,
	--[[
		Tvar jedné dlaždice podlahy. "Block" | "Ball" | "Cylinder".

		Měkké levely mají polštářky, tvrdé hranaté kostky — podlaha tím
		nese materiál i tvarem, ne jen barvou. Je to ta samá myšlenka
		jako u drobností: jeden tvar přes celou trať se z výšky očí
		slije v jednu plochu.
	]]
	TileShape: string,
	--[[
		Jak hluboko se pod hráčem prohne podlaha, stěny a strop. Odvozeno
		od `Squish`, ale zvlášť: máslo se prohýbá jinak, než jak vypadá,
		a chrom se neprohne vůbec.
	]]
	Sag: number,
	--[[
		Jak vypadá sbíratelná drobnost v tomhle levelu. Pickup je to, na co
		se hráč dívá nejvíc — když má přes celou trať jeden tvar a jednu
		barvu, splyne mu to v jeden nekonečný pás a postup přestane být
		vidět přesně tam, kde se kouká.
	]]
	Pickup: {
		-- "Ball" | "Block" | "Cylinder"; jméno, ne enum — čte to i server
		Shape: string,
		Color: Color3,
		-- Otáčí se kolem svislé osy? Kostka ano, kulička je na tom stejně
		Spin: boolean,
	},
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

--[[
	Dvanáct levelů na dvanáct zdí.

	Řada jde od nejměkčího k nejtvrdšímu ve všech rovinách naráz:

	  hmota   blob → marshmallow → máslo → mochi → želé → kobliha
	          → broskev → chleba → sýr → cukrové sklo → chrom → void
	  tvar    hodně měkký → tvrdý (viz `Squish` a `Sag`)
	  zvuk    mokré stlačení → tlumené žuchnutí → lepkavé odtržení
	          → křupnutí → kovový úder → nasáté ticho

	Když jde všechno jedním směrem, hráč pozná postup i se zavřenýma
	očima. Kdyby si roviny odporovaly (měkký zvuk na chromu), působilo by
	to jako chyba, ne jako styl.
]]
Zones.List = {
	{
		Id = "Blob",
		Name = "Blob Flats",
		From = 1,
		Toy = "Blob",
		-- Ta samá malinová růžová jako hračka, jen zesvětlená do plochy
		Floor = rgb(255, 168, 202),
		Edge = rgb(255, 222, 236),
		Tile = rgb(214, 96, 150),
		Ceiling = rgb(214, 118, 160),
		Material = "SmoothPlastic",
		WallMaterial = "SmoothPlastic",
		Sound = "Blob",
		Pattern = "dots",
		Decor = "bubbles",
		Reflectance = 0.12,
		Transparency = 0,
		Squish = 1,
		TileShape = "Ball",
		Sag = 1,
		Pickup = { Shape = "Ball", Color = rgb(214, 52, 132), Spin = false },
	},
	{
		Id = "Foam",
		Name = "Marshmallow Field",
		From = 2,
		Toy = "Foam",
		Floor = rgb(255, 246, 240),
		Edge = rgb(255, 214, 196),
		Tile = rgb(236, 190, 168),
		Ceiling = rgb(236, 208, 196),
		Material = "SmoothPlastic",
		WallMaterial = "SmoothPlastic",
		Sound = "Foam",
		Pattern = "sprinkles",
		Decor = "bubbles",
		Reflectance = 0.1,
		Transparency = 0,
		Squish = 0.95,
		TileShape = "Ball",
		Sag = 0.95,
		Pickup = { Shape = "Block", Color = rgb(255, 148, 108), Spin = true },
	},
	{
		Id = "Butter",
		Name = "Butter Block",
		From = 3,
		Toy = "Butter",
		-- Máslová žlutá přímo z těch squishy videí
		Floor = rgb(250, 236, 168),
		Edge = rgb(255, 250, 214),
		Tile = rgb(222, 186, 84),
		Ceiling = rgb(214, 194, 118),
		Material = "SmoothPlastic",
		WallMaterial = "SmoothPlastic",
		Sound = "Butter",
		Pattern = "checker",
		-- Papírový pás přes stěny, jako obal na hračce
		Decor = "wrapper",
		Reflectance = 0.2,
		Transparency = 0,
		Squish = 0.9,
		TileShape = "Block",
		Sag = 0.92,
		Pickup = { Shape = "Cylinder", Color = rgb(255, 186, 60), Spin = true },
	},
	{
		Id = "Mochi",
		Name = "Mochi Hills",
		From = 4,
		Toy = "Mochi",
		Floor = rgb(255, 240, 244),
		Edge = rgb(255, 208, 224),
		Tile = rgb(236, 176, 200),
		Ceiling = rgb(226, 196, 208),
		Material = "SmoothPlastic",
		WallMaterial = "SmoothPlastic",
		Sound = "Mochi",
		Pattern = "rings",
		Decor = "dust",
		Reflectance = 0.05,
		Transparency = 0,
		Squish = 0.84,
		TileShape = "Ball",
		Sag = 0.88,
		Pickup = { Shape = "Ball", Color = rgb(226, 108, 150), Spin = false },
	},
	{
		Id = "Jelly",
		Name = "Jelly Deep",
		From = 5,
		Toy = "Jelly",
		Floor = rgb(236, 96, 128),
		Edge = rgb(255, 176, 196),
		Tile = rgb(176, 52, 90),
		Ceiling = rgb(178, 62, 96),
		Material = "Glass",
		WallMaterial = "Glass",
		Sound = "Jelly",
		Pattern = "marble",
		Decor = "bubbles",
		Reflectance = 0.3,
		-- Jediný level, kde je vidět skrz podlahu; želé není neprůhledné
		Transparency = 0.15,
		Squish = 0.78,
		TileShape = "Ball",
		Sag = 0.85,
		Pickup = { Shape = "Ball", Color = rgb(255, 244, 140), Spin = false },
	},
	{
		Id = "Donut",
		Name = "Donut Ring",
		From = 6,
		Toy = "Donut",
		Floor = rgb(255, 176, 128),
		Edge = rgb(255, 224, 190),
		Tile = rgb(214, 118, 66),
		Ceiling = rgb(198, 124, 84),
		Material = "SmoothPlastic",
		WallMaterial = "SmoothPlastic",
		Sound = "Donut",
		Pattern = "stripes",
		-- Posyp: barevné tyčinky rozházené po podlaze i po stěnách
		Decor = "sprinkles",
		Reflectance = 0.16,
		Transparency = 0,
		Squish = 0.7,
		TileShape = "Cylinder",
		Sag = 0.74,
		Pickup = { Shape = "Cylinder", Color = rgb(255, 120, 170), Spin = true },
	},
	{
		Id = "Peach",
		Name = "Peach Orchard",
		From = 7,
		Toy = "Peach",
		-- Růžovočervená, ne oranžová: vedle koblihového levelu by
		-- oranžová vypadala jako ta samá chodba o kus dál
		Floor = rgb(246, 120, 148),
		Edge = rgb(255, 196, 208),
		Tile = rgb(198, 70, 104),
		Ceiling = rgb(186, 78, 104),
		Material = "SmoothPlastic",
		WallMaterial = "SmoothPlastic",
		Sound = "Peach",
		Pattern = "crumbs",
		Decor = "dust",
		Reflectance = 0.14,
		Transparency = 0,
		Squish = 0.62,
		TileShape = "Ball",
		Sag = 0.66,
		Pickup = { Shape = "Ball", Color = rgb(126, 208, 96), Spin = false },
	},
	{
		Id = "Bread",
		Name = "Toast Lane",
		From = 8,
		Toy = "Loaf",
		Floor = rgb(238, 196, 132),
		Edge = rgb(255, 232, 190),
		Tile = rgb(188, 138, 76),
		Ceiling = rgb(172, 126, 74),
		Material = "Sand",
		WallMaterial = "Sand",
		Sound = "Bread",
		Pattern = "bricks",
		-- Kůrka: tmavší pruhy podél okrajů
		Decor = "crust",
		Reflectance = 0.04,
		Transparency = 0,
		Squish = 0.52,
		TileShape = "Block",
		Sag = 0.55,
		Pickup = { Shape = "Block", Color = rgb(120, 86, 40), Spin = true },
	},
	{
		Id = "Cheese",
		Name = "Cheese Caves",
		From = 9,
		Toy = "Cheese",
		Floor = rgb(250, 232, 150),
		Edge = rgb(255, 246, 200),
		Tile = rgb(216, 184, 78),
		Ceiling = rgb(206, 178, 88),
		Material = "SmoothPlastic",
		WallMaterial = "SmoothPlastic",
		Sound = "Cheese",
		Pattern = "holes",
		-- Díry: to, podle čeho je sýr sýr
		Decor = "holes",
		Reflectance = 0.22,
		Transparency = 0,
		Squish = 0.42,
		TileShape = "Block",
		Sag = 0.44,
		Pickup = { Shape = "Block", Color = rgb(255, 176, 60), Spin = true },
	},
	{
		Id = "Glass",
		Name = "Sugar Glass",
		From = 10,
		Toy = "Candy",
		Floor = rgb(196, 240, 255),
		Edge = rgb(240, 252, 255),
		Tile = rgb(128, 196, 226),
		Ceiling = rgb(140, 196, 226),
		Material = "Glass",
		WallMaterial = "Glass",
		Sound = "Glass",
		Pattern = "grid",
		Decor = "shards",
		Reflectance = 0.45,
		Transparency = 0.12,
		Squish = 0.26,
		TileShape = "Block",
		Sag = 0.24,
		Pickup = { Shape = "Block", Color = rgb(120, 226, 255), Spin = true },
	},
	{
		Id = "Chrome",
		Name = "Chrome Mile",
		From = 11,
		Toy = "Ball",
		Floor = rgb(226, 234, 250),
		Edge = rgb(255, 255, 255),
		Tile = rgb(166, 180, 208),
		Ceiling = rgb(158, 170, 196),
		Material = "Metal",
		WallMaterial = "Metal",
		Sound = "Chrome",
		Pattern = "lanes",
		Decor = "rivets",
		Reflectance = 0.85,
		Transparency = 0,
		Squish = 0.1,
		TileShape = "Block",
		Sag = 0.08,
		Pickup = { Shape = "Ball", Color = rgb(140, 255, 236), Spin = false },
	},
	{
		Id = "Void",
		Name = "Void Core",
		From = 12,
		Toy = "Core",
		Floor = rgb(46, 30, 86),
		Edge = rgb(178, 140, 255),
		Tile = rgb(120, 86, 196),
		Ceiling = rgb(28, 18, 56),
		Material = "Glass",
		WallMaterial = "ForceField",
		Sound = "Void",
		Pattern = "waves",
		Decor = "shards",
		Reflectance = 0.55,
		Transparency = 0,
		--[[
			Nula, i když Void zní měkce. `Squish` popisuje **povrch**,
			a sklo měkké není; ten sjezd výšky dolů je o nasátí, ne
			o stlačení hmoty. Kdyby tu byla vyšší hodnota, rozešel by se
			tvar podlahy s materiálem — a hráč by to viděl jako chybu.
		]]
		Squish = 0,
		TileShape = "Block",
		Sag = 0,
		Pickup = { Shape = "Block", Color = rgb(196, 150, 255), Spin = true },
	},
} :: { Zone }

--[[
	Známé druhy povrchové výzdoby. Neznámý druh se nepostaví, takže
	překlep v `Decor` znamená hladkou stěnu — ne pád.
]]
Zones.Decors = { "bubbles", "wrapper", "dust", "sprinkles", "crust", "holes", "shards", "rivets" }

function Zones.hasDecor(kind: string): boolean
	return table.find(Zones.Decors, kind) ~= nil
end

--[[
	Zóna pro danou bariéru. Bere poslední, jejíž `From` je menší nebo
	rovno — takže se seznam dá rozšířit přidáním řádku a nic dalšího
	se měnit nemusí.
]]
function Zones.at(barrierIndex: number): Zone
	local best = Zones.List[1]

	for _, zone in Zones.List do
		if barrierIndex >= zone.From then
			best = zone
		end
	end

	return best
end

function Zones.indexAt(barrierIndex: number): number
	local best = 1

	for index, zone in Zones.List do
		if barrierIndex >= zone.From then
			best = index
		end
	end

	return best
end

-- Poslední bariéra, kterou zóna ještě pokrývá.
function Zones.lastBarrier(zoneIndex: number): number
	local next = Zones.List[zoneIndex + 1]
	if next then
		return next.From - 1
	end
	return Config.Track.BarrierCount
end

-- Začíná u téhle bariéry nová zóna? Podle toho se staví cedule.
function Zones.startsAt(barrierIndex: number): Zone?
	for _, zone in Zones.List do
		if zone.From == barrierIndex then
			return zone
		end
	end
	return nil
end

--[[
	Paleta levelu obarvená podle světa.

	Levely se do teď vykreslovaly ve všech světech úplně stejně. Svět
	měnil halu, oblohu, mlhu, rekvizity a barvu zdí — ale podlaha, po
	které hráč běhá a na kterou se dívá nejvíc, byla v Infinity Garden
	na chlup stejná jako v Glass Hall. Deset světů tím pádem vypadalo
	jako deset různých pozadí kolem jedné a té samé trati.

	Barva se proto přimíchává, ne nahrazuje: máslo zůstane žluté a sýr
	má pořád díry, ale v Solar Forge jsou spálené a v Quantum Bloom
	bledé. Z dvanácti opakovaných úseků je tím sto dvacet různých.

	Míchá se jen `alpha` dílu barvy — materiál, vzor, tvar dlaždice
	i výzdoba zůstávají levelu. Kdyby se měnily i ty, přestal by být
	level poznat a zbylo by z něj jen "další barevná chodba".
]]
export type Palette = {
	Floor: Color3,
	Edge: Color3,
	Tile: Color3,
	Ceiling: Color3,
}

function Zones.palette(zone: Zone, world: any): Palette
	local tint = world and world.Color
	local amount = if world and world.Tint then world.Tint else 0

	if not tint or amount <= 0 then
		return {
			Floor = zone.Floor,
			Edge = zone.Edge,
			Tile = zone.Tile,
			Ceiling = zone.Ceiling,
		}
	end

	--[[
		Lem a strop snesou víc než podlaha. Podlaha nese kresbu vzoru
		a ta se ztratí, jakmile se obě její barvy sblíží — proto se
		`Floor` a `Tile` míchají slaběji než zbytek.
	]]
	return {
		Floor = zone.Floor:Lerp(tint, amount * 0.7),
		Edge = zone.Edge:Lerp(tint, amount),
		Tile = zone.Tile:Lerp(tint, amount * 0.7),
		Ceiling = zone.Ceiling:Lerp(tint, amount),
	}
end

--[[
	Level, ve kterém hračka stojí jako obří rekvizita.

	Bez tohohle je řádek v obchodě jen jméno a cena a hráč nemá jak
	spojit "Cheese Cube za 260 miliard" s tím obřím sýrem, kolem
	kterého v devátém levelu proběhl.
]]
function Zones.levelFor(toyId: string): (Zone?, number?)
	for index, zone in Zones.List do
		if zone.Toy == toyId then
			return zone, index
		end
	end

	return nil, nil
end

--[[
	Z jaké hmoty hračka je.

	Hračka a level k sobě patří, takže recept zvuku není potřeba psát
	podruhé do katalogu hraček — kdyby byl, rozešly by se levely se
	sbírkou při první úpravě jednoho z nich.

	Hračka bez levelu (odměna za sedmý den) spadne na sklo. Němá hračka
	v ruce je horší než hračka, která zní o kus vedle.
]]
function Zones.soundForToy(toyId: string): string
	local zone = Zones.levelFor(toyId)
	return if zone then zone.Sound else "Glass"
end

return Zones

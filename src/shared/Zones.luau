--!strict
--[[
	Zones — terén, který se mění pod nohama podle toho, jak daleko jsi.

	Do teď měl celý svět jeden materiál a jednu barvu. Hráč tak proběhl
	dvanáct zdí a pod nohama měl pořád totéž: postup byl jen v číslech,
	ne v tom, co vidí a slyší.

	Trať je teď rozdělená na **zóny**. Každá pokrývá několik úseků mezi
	zdmi a má vlastní barvu podlahy, materiál, výšku kroku a odstín světla.
	Přechod přes zeď tedy není jen "další číslo", ale jiné místo.

	Zóna se určuje z indexu bariéry, ne z pozice: server ověřuje průraz
	podle indexu, takže z něj musí vycházet i všechno ostatní, jinak by
	se obojí mohlo rozejít.

	Zvuk kroku je jen výška vzorku, ne nová nahrávka — stejný trik jako
	u zbytku hry. Vyšší tón zní tvrději, nižší měkčeji, a mezi zónami
	je to slyšet okamžitě.
]]

local Config = require(script.Parent.Config)

local Zones = {}

export type Zone = {
	Id: string,
	Name: string,
	-- Od které bariéry zóna platí (včetně)
	From: number,
	Floor: Color3,
	Edge: Color3,
	-- Jméno z Enum.Material, ne samotný enum: modul čte i server
	Material: string,
	-- Materiál zdi v téhle zóně; často jiný než podlaha
	WallMaterial: string,
	-- Klíč do Assets.Terrain — vlastní recept kroku i průrazu
	Sound: string,
	Reflectance: number,
	Transparency: number,
	-- Jak moc má podlaha "měkký" tvar: vyšší = zaoblenější lem
	Squish: number,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

--[[
	Šest zón na dvanáct zdí — každá tedy pokrývá dva úseky.

	Vzhled je odkoukaný ze squishy hraček: **krémové pastely, hladký
	povrch, jemný lesk**. Máslo, sýr, mochi, jahoda. Právě proto je
	skoro všude `SmoothPlastic` s malou odrazivostí — je to jediný
	materiál v Robloxu, který vypadá jako měkký vinyl. Drsné materiály
	(`Mud`, `Sand`, `Slate`) tenhle dojem zabíjejí, i když by "seděly"
	tematicky.

	Řada jde od nejměkčí k nejtvrdší ve všech třech rovinách naráz:

	  lesk    0,10 → 0,15 → 0,22 → 0,45 → 0,85 → 0,55
	  zvuk    mokré stlačení → tlumené žuchnutí → lepkavé odtržení
	          → křupnutí → kovový úder → nasáté ticho
	  tvar    hodně měkký → tvrdý (viz `Squish`)

	Když jde všechno jedním směrem, hráč pozná postup i se zavřenýma
	očima. Kdyby si roviny odporovaly (měkký zvuk na kovu), působilo by
	to jako chyba, ne jako styl.
]]
Zones.List = {
	{
		Id = "Jelly",
		Name = "Jelly Flats",
		From = 1,
		-- Jahodové mochi: sytá, ale bledá — pastel, ne neon
		Floor = rgb(255, 176, 206),
		Edge = rgb(255, 224, 236),
		Material = "SmoothPlastic",
		WallMaterial = "SmoothPlastic",
		Sound = "Jelly",
		Reflectance = 0.1,
		Transparency = 0,
		Squish = 1,
	},
	{
		Id = "Foam",
		Name = "Marshmallow",
		From = 3,
		Floor = rgb(255, 246, 240),
		Edge = rgb(255, 214, 196),
		Material = "SmoothPlastic",
		WallMaterial = "SmoothPlastic",
		Sound = "Foam",
		Reflectance = 0.15,
		Transparency = 0,
		Squish = 0.85,
	},
	{
		Id = "Caramel",
		Name = "Butter Block",
		From = 5,
		-- Máslová žlutá přímo z těch squishy videí
		Floor = rgb(252, 224, 132),
		Edge = rgb(255, 244, 196),
		Material = "SmoothPlastic",
		WallMaterial = "SmoothPlastic",
		Sound = "Caramel",
		Reflectance = 0.22,
		Transparency = 0,
		Squish = 0.6,
	},
	{
		Id = "Glass",
		Name = "Sugar Glass",
		From = 7,
		Floor = rgb(196, 240, 255),
		Edge = rgb(240, 252, 255),
		Material = "Glass",
		WallMaterial = "Glass",
		Sound = "Glass",
		Reflectance = 0.45,
		Transparency = 0.12,
		Squish = 0.2,
	},
	{
		Id = "Chrome",
		Name = "Chrome Mile",
		From = 9,
		Floor = rgb(226, 234, 250),
		Edge = rgb(255, 255, 255),
		Material = "Metal",
		WallMaterial = "Metal",
		Sound = "Chrome",
		Reflectance = 0.85,
		Transparency = 0,
		Squish = 0,
	},
	{
		Id = "Void",
		Name = "Void Edge",
		From = 11,
		Floor = rgb(46, 30, 86),
		Edge = rgb(178, 140, 255),
		Material = "Glass",
		WallMaterial = "ForceField",
		Sound = "Void",
		Reflectance = 0.55,
		Transparency = 0,
		--[[
			Nula, i když Void zní měkce. `Squish` popisuje **podlahu**,
			a sklo měkké není; ten sjezd výšky dolů je o nasátí, ne
			o stlačení hmoty. Kdyby tu byla vyšší hodnota, rozešel by se
			tvar podlahy s materiálem — a hráč by to viděl jako chybu.
		]]
		Squish = 0,
	},
} :: { Zone }

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

return Zones

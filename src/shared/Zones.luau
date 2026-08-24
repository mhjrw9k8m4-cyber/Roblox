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
	Material: string,
	-- Násobek výšky u zvuku kroku: nižší = měkčí, vyšší = tvrdší
	StepPitch: number,
	-- Jak moc je podlaha lesklá; nastavuje se přímo na díly
	Reflectance: number,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

--[[
	Šest zón na dvanáct zdí — každá tedy pokrývá dva úseky.

	Jdou od měkkého a tmavého k tvrdému a zářivému: hráč tím fyzicky
	vidí, že postoupil, ještě než se podívá na číslo.
]]
Zones.List = {
	{
		Id = "Foam",
		Name = "Foam Flats",
		From = 1,
		Floor = rgb(126, 62, 190),
		Edge = rgb(172, 100, 232),
		Material = "Fabric",
		StepPitch = 0.8,
		Reflectance = 0,
	},
	{
		Id = "Candy",
		Name = "Candy Path",
		From = 3,
		Floor = rgb(255, 106, 178),
		Edge = rgb(255, 158, 214),
		Material = "Plastic",
		StepPitch = 1.1,
		Reflectance = 0.06,
	},
	{
		Id = "Glass",
		Name = "Glass Run",
		From = 5,
		Floor = rgb(150, 226, 255),
		Edge = rgb(226, 250, 255),
		Material = "Glass",
		StepPitch = 1.6,
		Reflectance = 0.3,
	},
	{
		Id = "Metal",
		Name = "Chrome Mile",
		From = 7,
		Floor = rgb(196, 206, 226),
		Edge = rgb(255, 255, 255),
		Material = "Metal",
		StepPitch = 2.0,
		Reflectance = 0.7,
	},
	{
		Id = "Neon",
		Name = "Neon Strip",
		From = 9,
		Floor = rgb(168, 255, 88),
		Edge = rgb(96, 226, 255),
		Material = "Neon",
		StepPitch = 2.4,
		Reflectance = 0,
	},
	{
		Id = "Void",
		Name = "Void Edge",
		From = 11,
		Floor = rgb(40, 22, 78),
		Edge = rgb(150, 86, 255),
		Material = "Slate",
		StepPitch = 0.55,
		Reflectance = 0.45,
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

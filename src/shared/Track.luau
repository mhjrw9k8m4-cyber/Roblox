--!strict
--[[
	Track — geometrie tratě spočítaná, ne postavená.

	Server i klient potřebují vědět, kde přesně leží bariéry a pickupy:
	klient je staví, server podle nich ověřuje, že hráč opravdu byl u toho,
	co tvrdí. Kdyby si každá strana počítala pozice po svém, exploit by
	vznikl už jen z toho, že se rozešly.
]]

local Config = require(script.Parent.Config)

local Track = {}

local TRACK = Config.Track

Track.PickupsPerRow = #TRACK.Lanes
Track.PickupsPerSegment = #TRACK.Lanes * #TRACK.RowOffsets
Track.PickupCount = Track.PickupsPerSegment * TRACK.BarrierCount

-- Světy leží vedle sebe na ose X, aby se daly postavit všechny naráz
function Track.origin(worldIndex: number): Vector3
	return Vector3.new((worldIndex - 1) * TRACK.WorldSpacing, 0, 0)
end

function Track.spawnCFrame(worldIndex: number): CFrame
	return CFrame.new(Track.origin(worldIndex) + Vector3.new(0, 4, -22))
end

function Track.barrierPosition(worldIndex: number, index: number): Vector3
	return Track.origin(worldIndex) + Vector3.new(0, 6, TRACK.SegmentLength * index)
end

function Track.finishPosition(worldIndex: number): Vector3
	return Track.origin(worldIndex)
		+ Vector3.new(0, 4, TRACK.SegmentLength * (TRACK.BarrierCount + 1) - 20)
end

--[[
	Zlaté pickupy.

	Malá část pickupů stojí mnohonásobek. Jde o jediný moment na trati,
	který se nedá odhadnout dopředu — všechno ostatní je pravidelné,
	a hra, ve které nikdy nic nepřekvapí, se přestane hrát.

	Které to jsou, se NEPOSÍLÁ po síti. Odvozuje se to čistě z čísel,
	která obě strany stejně znají (svět, kolo, index pickupu), takže
	server i klient dojdou k témuž bez jediného bajtu navíc — a hráč
	si sadu nemůže vybrat.

	Míchá se přes `bit32`, ne přes operátor `~` — ten Luau nezná.

	Násobitele jsou schválně **šestnáctibitové**. Luau počítá v doublech,
	takže součin dvou třicetidvoubitových čísel přeteče přesnost (2^53)
	a spodní bity, na kterých celý hash stojí, se tiše ztratí. S 16bitovým
	násobitelem zůstane součin bezpečně pod hranicí.

	První verze jen provázala tři součiny přes XOR. Vypadalo to dobře
	a test to shodil: v některých kombinacích světa a kola nevyšel ani
	jeden zlatý pickup a v prvním světě seděly v pravidelném rozestupu.
	Málo míchání se nepozná jinak než měřením — proto ten test.
]]
local function mix(value: number): number
	local n = bit32.band(value, 0xFFFFFFFF)

	n = bit32.bxor(n, bit32.rshift(n, 15))
	n = bit32.band(n * 0x9E37, 0xFFFFFFFF)
	n = bit32.bxor(n, bit32.rshift(n, 13))
	n = bit32.band(n * 0x85EB, 0xFFFFFFFF)
	n = bit32.bxor(n, bit32.rshift(n, 16))

	return n
end

--[[
	Jeden zlatý pickup je v každém světě a kole JISTÝ.

	Losování samo o sobě nestačí: při dvaadvaceti promile a stovce
	pickupů vyjde na jeden svět a kolo v průměru čtyři, ale občas
	nevyjde ani jeden — a hráč, který zrovna na takový běh narazí,
	o mechanice vůbec neví. Přes deset světů a několik kol je jistota,
	že se to stane, ne možnost.

	Který to je, se počítá z toho samého míchání, takže se klient
	i server trefí do stejného a po síti se nic posílat nemusí.
]]
local function guaranteedGolden(worldIndex: number, lap: number): number
	return mix(worldIndex * 31 + lap * 977) % Track.PickupCount + 1
end

function Track.isGolden(worldIndex: number, lap: number, pickupIndex: number): boolean
	if pickupIndex == guaranteedGolden(worldIndex, lap) then
		return true
	end

	local seed = pickupIndex + worldIndex * 7919 + (lap + 1) * 104729
	return mix(seed) % 1000 < TRACK.GoldenPerMille
end

--[[
	Šťastná zeď.

	Ta samá myšlenka jako u zlatého pickupu, ale na zdech: nepravidelná
	odměna drží pozornost líp než pravidelná. Hráč nemůže vědět, která
	zeď to bude, takže se dívá na každou.

	Počítá se ze stejného míchání jako všechno ostatní, jen s jinou
	solí — klient i server se trefí do stejné zdi a nikdo si ji nemůže
	vybrat. Kolo je v soli taky, jinak by v každém kole padly jackpoty
	na těch samých místech a hráč by si je zapamatoval.
]]
function Track.isJackpot(worldIndex: number, lap: number, barrierIndex: number): boolean
	--[[
		V úplně prvním kole je jedna šťastná zeď jistá.

		Při třiceti promile má dvanáctizeďové kolo asi třetinovou šanci,
		že v něm nějaká bude — takže část hráčů by o mechanice za první
		sezení vůbec nevěděla. Mechanika, kterou hráč nikdy neuvidí,
		nedrží pozornost, ať je nastavená jakkoliv.

		Devátá zeď schválně: dost pozdě na to, aby už hráč smyčku znal,
		a dost brzo na to, aby to stihl v prvním sezení. Platí to jen
		jednou za celou hru, takže to ekonomiku nehne.
	]]
	if worldIndex == 1 and lap == 0 and barrierIndex == 9 then
		return true
	end

	local seed = barrierIndex * 6151 + worldIndex * 24593 + (lap + 1) * 49157
	return mix(seed) % 1000 < TRACK.JackpotPerMille
end

function Track.length(): number
	return TRACK.SegmentLength * (TRACK.BarrierCount + 1)
end

--[[
	Pickupy jsou číslované průběžně od 1. Index se dá rozložit zpátky
	na segment / řadu / sloupec, takže stačí posílat po síti jedno číslo.
]]
function Track.pickupPosition(worldIndex: number, pickupIndex: number): Vector3?
	if pickupIndex < 1 or pickupIndex > Track.PickupCount then
		return nil
	end

	local zeroBased = pickupIndex - 1
	local segment = zeroBased // Track.PickupsPerSegment -- 0..BarrierCount-1
	local withinSegment = zeroBased % Track.PickupsPerSegment
	local row = withinSegment // Track.PickupsPerRow -- 0..#RowOffsets-1
	local lane = withinSegment % Track.PickupsPerRow -- 0..#Lanes-1

	--[[
		Vyvýšená řada. Počítá se tady, protože z týhle jediné funkce
		staví klient pickupy a server podle ní ověřuje dosah — kdyby
		si výšku přidával jen klient, server by sebrání odmítl.
	]]
	local height = if row + 1 == TRACK.RaisedRow then 3.5 + TRACK.RaisedHeight else 3.5

	return Track.origin(worldIndex)
		+ Vector3.new(
			TRACK.Lanes[lane + 1],
			height,
			TRACK.SegmentLength * segment + TRACK.RowOffsets[row + 1]
		)
end

-- Do kterého segmentu (a tedy před kterou bariéru) pickup patří
function Track.pickupSegment(pickupIndex: number): number
	return (pickupIndex - 1) // Track.PickupsPerSegment + 1
end

-- Všechny pickupy jednoho segmentu — klient podle toho staví trať po částech
function Track.segmentPickups(segment: number): { number }
	local first = (segment - 1) * Track.PickupsPerSegment + 1
	local indices = table.create(Track.PickupsPerSegment)
	for offset = 0, Track.PickupsPerSegment - 1 do
		indices[offset + 1] = first + offset
	end
	return indices
end

return Track

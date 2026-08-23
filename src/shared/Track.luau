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

	return Track.origin(worldIndex)
		+ Vector3.new(
			TRACK.Lanes[lane + 1],
			3.5,
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

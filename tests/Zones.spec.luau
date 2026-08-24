--!strict
--[[
	Zóny — terén, který se mění pod hráčem podle toho, jak daleko je.

	Zóna se určuje z indexu bariéry. Server podle indexu ověřuje průraz,
	takže se z něj musí odvíjet i všechno ostatní — kdyby se to rozešlo,
	hráč by stál na jednom terénu a slyšel jiný.
]]

return function(t)
	local Zones = t.require("Zones")
	local Config = t.require("Config")

	local BARRIERS = Config.Track.BarrierCount

	t.test("první zóna začíná u první zdi", function()
		t.equal(Zones.List[1].From, 1, "trať by začínala bez terénu")
	end)

	t.test("zóny jdou po sobě a nepřekrývají se", function()
		for index = 2, #Zones.List do
			t.assert(
				Zones.List[index].From > Zones.List[index - 1].From,
				`zóna {index} začíná dřív než ta před ní`
			)
		end
	end)

	t.test("každá zeď patří právě do jedné zóny", function()
		for barrier = 1, BARRIERS do
			local zone = Zones.at(barrier)
			t.assert(zone ~= nil, `zeď {barrier} nemá zónu`)
			t.assert(barrier >= zone.From, `zeď {barrier} dostala zónu, která ještě nezačala`)
		end
	end)

	--[[
		Zóna, která začíná až za poslední zdí, by se ve hře nikdy
		neobjevila — byla by to jen mrtvá data v konfiguraci.
	]]
	t.test("každá zóna je dosažitelná", function()
		for index, zone in Zones.List do
			t.assert(
				zone.From <= BARRIERS,
				`zóna {zone.Id} začíná u zdi {zone.From}, ale trať má jen {BARRIERS}`
			)
			t.assert(Zones.lastBarrier(index) >= zone.From, `zóna {zone.Id} nepokrývá ani jednu zeď`)
		end
	end)

	t.test("terén se během trati opravdu vystřídá", function()
		local seen = {}
		for barrier = 1, BARRIERS do
			seen[Zones.at(barrier).Id] = true
		end

		local count = 0
		for _ in seen do
			count += 1
		end

		t.assert(count >= 3, `hráč po celé trati potká jen {count} druh(y) terénu`)
	end)

	t.test("cedule stojí právě tam, kde zóna začíná", function()
		for barrier = 1, BARRIERS do
			local starts = Zones.startsAt(barrier)
			local zone = Zones.at(barrier)

			if starts then
				t.equal(starts.Id, zone.Id, `cedule u zdi {barrier} patří jiné zóně`)
			end
		end

		-- Ceduli musí dostat každá zóna, jinak by se terén změnil bez varování
		local signs = 0
		for barrier = 1, BARRIERS do
			if Zones.startsAt(barrier) then
				signs += 1
			end
		end
		t.equal(signs, #Zones.List, "některá zóna nemá ceduli")
	end)

	t.test("index zóny sedí na seznam", function()
		for barrier = 1, BARRIERS do
			local index = Zones.indexAt(barrier)
			t.equal(Zones.List[index].Id, Zones.at(barrier).Id, `index u zdi {barrier} neodpovídá`)
		end
	end)

	--[[
		Materiál se drží jako jméno, ne jako enum: modul čte i server,
		kde by konkrétní enum nikomu k ničemu nebyl. Překlep by se jinak
		projevil až na klientovi, a jen v jedné zóně.
	]]
	t.test("každá zóna má materiál, který v Robloxu existuje", function()
		for _, zone in Zones.List do
			t.assert(
				(Enum.Material :: any)[zone.Material] ~= nil,
				`zóna {zone.Id}: neznámý materiál {zone.Material}`
			)
		end
	end)

	t.test("zvuk kroku se mezi zónami liší", function()
		local pitches = {}
		for _, zone in Zones.List do
			t.assert(zone.StepPitch > 0.3 and zone.StepPitch < 3, `{zone.Id}: výška mimo rozsah`)
			pitches[zone.StepPitch] = (pitches[zone.StepPitch] or 0) + 1
		end

		local distinct = 0
		for _ in pitches do
			distinct += 1
		end

		t.equal(distinct, #Zones.List, "dvě zóny znějí stejně — změna terénu nebude slyšet")
	end)

	t.test("id a jména jsou jedinečná", function()
		local ids, names = {}, {}
		for _, zone in Zones.List do
			t.assert(not ids[zone.Id], `dvakrát id {zone.Id}`)
			t.assert(not names[zone.Name], `dvakrát jméno {zone.Name}`)
			ids[zone.Id] = true
			names[zone.Name] = true
		end
	end)
end

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
	t.test("každá zóna má materiály, které v Robloxu existují", function()
		for _, zone in Zones.List do
			for _, field in { "Material", "WallMaterial" } do
				local name = (zone :: any)[field]
				t.assert(
					(Enum.Material :: any)[name] ~= nil,
					`zóna {zone.Id}: neznámý materiál {name} ({field})`
				)
			end
		end
	end)

	--[[
		Zóny mají jít od nejměkčí k nejtvrdší. Kdyby se pořadí rozešlo,
		hráč by uprostřed trati "změkl" a postup by přestal být cítit.
	]]
	t.test("terén tvrdne směrem k cíli", function()
		t.assert(Zones.List[1].Squish > Zones.List[#Zones.List].Squish
			or Zones.List[1].Squish >= 0.8, "první zóna není měkká")

		local softest = Zones.List[1].Squish
		for index = 2, #Zones.List do
			t.assert(
				Zones.List[index].Squish <= softest + 0.001,
				`zóna {Zones.List[index].Id} je měkčí než ta před ní`
			)
			softest = Zones.List[index].Squish
		end
	end)

	--[[
		Každá zóna má vlastní recept kroku i průrazu, ne jen jinou výšku
		téhož vzorku. Jinak by z toho byl "stejný zvuk, jen vyšší", ne
		jiný materiál.
	]]
	t.test("každá zóna má vlastní zvuk kroku i průrazu", function()
		local Assets = t.require("Assets")
		local seen = {}

		for _, zone in Zones.List do
			t.assert(not seen[zone.Sound], `dvě zóny sdílí zvuk {zone.Sound}`)
			seen[zone.Sound] = true

			for _, kind in { "Step", "Smash" } do
				local recipe = Assets.terrain(zone.Sound, kind)
				t.assert(#recipe > 0, `{zone.Id}/{kind}: prázdný recept`)

				for index, layer in recipe do
					t.assert(layer.Id ~= nil and layer.Id ~= "", `{zone.Id}/{kind}[{index}]: chybí zvuk`)
					t.assert(layer.Pitch > 0, `{zone.Id}/{kind}[{index}]: nulová výška`)
					t.assert(layer.Volume > 0, `{zone.Id}/{kind}[{index}]: nulová hlasitost`)
				end
			end
		end
	end)

	--[[
		Ohyb výšky je to jediné, co dělá "squishy" — sjezd dolů zní jako
		stlačení měkké hmoty. Měkké zóny ho tedy mít musí, jinak z nich
		bude jen jinak barevná podlaha.
	]]
	t.test("měkké zóny mají ohyb výšky", function()
		local Assets = t.require("Assets")

		for _, zone in Zones.List do
			if zone.Squish < 0.5 then
				continue
			end

			local bends = 0
			for _, layer in Assets.terrain(zone.Sound, "Step") do
				if layer.Bend then
					bends += 1
				end
			end

			t.assert(bends > 0, `měkká zóna {zone.Id} nemá v kroku ani jeden ohyb — nebude squishy`)
		end
	end)

	t.test("ohyb má vždy kladný cíl a rozumnou dobu", function()
		local Assets = t.require("Assets")

		for _, zone in Zones.List do
			for _, kind in { "Step", "Smash" } do
				for index, layer in Assets.terrain(zone.Sound, kind) do
					if layer.Bend then
						t.assert(layer.Bend > 0, `{zone.Id}/{kind}[{index}]: ohyb na nulu nebo pod ni`)
						local time = layer.BendTime or 0.12
						t.assert(time > 0.02 and time < 1.5, `{zone.Id}/{kind}[{index}]: doba ohybu {time}`)
					end
				end
			end
		end
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

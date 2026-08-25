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

	--[[
		Drobnost na trati je to, na co se hráč dívá nejvíc. Kdyby měly
		všechny zóny stejný tvar i barvu, splyne mu celá trať v jeden pás
		a postup zmizí právě tam, kde se dívá.
	]]
	t.test("každá zóna má vlastní drobnost a tvary se opravdu střídají", function()
		local SHAPES = { Ball = true, Block = true, Cylinder = true }

		local shapes = {}
		local colors = {}

		for _, zone in Zones.List do
			local pickup = zone.Pickup
			t.assert(pickup ~= nil, `zóna {zone.Id} nemá drobnost`)
			t.assert(SHAPES[pickup.Shape] == true, `zóna {zone.Id}: neznámý tvar {pickup.Shape}`)

			shapes[pickup.Shape] = true

			-- Barvy se porovnávají po složkách; Color3 se nedá dát do klíče
			local key = `{math.floor(pickup.Color.R * 255)},`
				.. `{math.floor(pickup.Color.G * 255)},`
				.. `{math.floor(pickup.Color.B * 255)}`
			t.assert(colors[key] == nil, `zóny {zone.Id} a {colors[key]} mají stejnou barvu drobnosti`)
			colors[key] = zone.Id
		end

		local distinct = 0
		for _ in shapes do
			distinct += 1
		end
		t.assert(distinct >= 3, `na trati jsou jen {distinct} tvar(y) drobností`)
	end)

	--[[
		Drobnost musí být vidět proti podlaze, na které leží. Dvě blízké
		barvy vypadají ve Studiu neškodně a ve hře se ztratí úplně.
	]]
	t.test("drobnost je vidět proti podlaze své zóny", function()
		for _, zone in Zones.List do
			local pickup = zone.Pickup
			local distance = math.abs(pickup.Color.R - zone.Floor.R)
				+ math.abs(pickup.Color.G - zone.Floor.G)
				+ math.abs(pickup.Color.B - zone.Floor.B)

			t.assert(
				distance > 0.25,
				`zóna {zone.Id}: drobnost splývá s podlahou (odstup {math.floor(distance * 100) / 100})`
			)
		end
	end)


	--[[
		Jeden level na jednu zeď. To je celý smysl přestavby: prorazíš
		a jsi jinde. Kdyby jeden level pokrýval dvě zdi, druhá z nich by
		vypadala jako "ta samá chodba, jen o kus dál".
	]]
	t.test("každá zeď má vlastní level", function()
		t.equal(#Zones.List, BARRIERS, `levelů je {#Zones.List}, zdí {BARRIERS}`)

		for barrier = 1, BARRIERS do
			t.equal(Zones.at(barrier).From, barrier, `zeď {barrier} sdílí level s jinou`)
		end
	end)

	--[[
		Sousední levely musí být poznat na první pohled. Dva blízké
		odstíny vedle sebe znamenají, že hráč projde zdí a nevšimne si
		toho — a pak celá přestavba nemá co dodat.
	]]
	t.test("sousední levely se od sebe liší barvou", function()
		local function distance(a: Color3, b: Color3): number
			return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B)
		end

		for index = 2, #Zones.List do
			local before, after = Zones.List[index - 1], Zones.List[index]
			local floors = distance(before.Floor, after.Floor)
			local ceilings = distance(before.Ceiling, after.Ceiling)

			t.assert(
				floors > 0.18 or ceilings > 0.25,
				`{before.Name} a {after.Name} vypadají skoro stejně (podlahy {math.floor(floors * 100) / 100})`
			)
		end
	end)

	--[[
		Chodba se prohýbá; `Sag` říká kolik. Musí klesat spolu se
		`Squish`, jinak by měkce vypadající level tuhle a tvrdý povolil.
	]]
	t.test("prohnutí chodby klesá spolu s měkkostí", function()
		local previous = math.huge

		for _, zone in Zones.List do
			t.assert(zone.Sag >= 0 and zone.Sag <= 1, `{zone.Id}: prohnutí {zone.Sag} je mimo rozsah`)
			t.assert(zone.Sag <= previous + 0.001, `{zone.Id} se prohýbá víc než level před ním`)
			previous = zone.Sag
		end

		t.assert(Zones.List[1].Sag > 0.5, "první level se skoro neprohýbá")
		t.assert(Zones.List[#Zones.List].Sag < 0.2, "poslední level je pořád měkký")
	end)

	--[[
		Level ušitý podle hračky na ni musí opravdu ukazovat. Překlep by
		znamenal, že hráč drží máslo a běží levelem, který se tváří jako
		máslo, ale bere barvy odjinud.
	]]
	t.test("odkaz na hračku míří na existující kus", function()
		local Live = t.require("Live")
		local linked = 0

		for _, zone in Zones.List do
			if zone.Toy then
				t.assert(Live.squishy(zone.Toy) ~= nil, `{zone.Id}: hračka {zone.Toy} neexistuje`)
				linked += 1
			end
		end

		t.assert(linked >= 6, `podle hraček je ušitých jen {linked} levelů`)
	end)

	t.test("každý level má známý druh výzdoby", function()
		for _, zone in Zones.List do
			t.assert(Zones.hasDecor(zone.Decor), `{zone.Id}: neznámá výzdoba {zone.Decor}`)
		end
	end)

end

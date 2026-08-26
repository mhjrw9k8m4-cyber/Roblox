--!strict
--[[
	Události v hale.

	Nahradily jediné okno "×2 mince na půl hodiny" — to bylo pořád to
	samé a hráč se na něj po druhém přestal dívat. Střídají se čtyři
	a pointa je v tom, že hráč neví, co přijde, ale pořád vidí, kdy.

	Počítá se to z času, ne ze stavu, takže se hlavně testuje, že se
	ta dvě čísla (jak často, jak dlouho) nedají nastavit tak, aby
	událost buď nikdy neskončila, nebo nikdy nezačala.
]]

return function(t)
	local Economy = t.require("Economy")
	local Live = t.require("Live")

	local EVERY = Live.Events.EverySeconds
	local LENGTH = Live.Events.LengthSeconds
	local ROTATION = Live.Events.Rotation

	t.test("okno je kratší než rozestup", function()
		t.assert(LENGTH > 0, "událost má nulovou délku, nikdy nezačne")
		t.assert(
			LENGTH < EVERY,
			`událost trvá {LENGTH} s a opakuje se po {EVERY} s — nikdy by neskončila`
		)
	end)

	t.test("událost začíná na začátku rozestupu a končí po své délce", function()
		t.assert(Economy.eventAt(0).Active ~= nil, "na začátku nic neběží")
		t.assert(Economy.eventAt(LENGTH - 1).Active ~= nil, "těsně před koncem už neběží")
		t.equal(Economy.eventAt(LENGTH).Active, nil, "událost neskončila, když měla")
		t.equal(Economy.eventAt(EVERY - 1).Active, nil, "těsně před další už běží")
		t.assert(Economy.eventAt(EVERY).Active ~= nil, "další událost nezačala")
	end)

	--[[
		Odpočty musí ubývat a nikdy neukázat nulu, když se čeká. Karta
		v HUD stojí na obou: "kolik zbývá" během události a "za jak
		dlouho" mezi nimi.
	]]
	t.test("odpočty ubývají a nikdy nestojí", function()
		t.equal(Economy.eventAt(0).Remaining, LENGTH, "na začátku nesedí celá délka")
		t.equal(Economy.eventAt(LENGTH - 10).Remaining, 10, "odpočet neubývá po sekundách")
		t.equal(Economy.eventAt(LENGTH).Remaining, 0, "po konci zbývá čas")

		t.equal(Economy.eventAt(LENGTH).Until, EVERY - LENGTH, "odpočet do další nesedí")
		t.assert(Economy.eventAt(EVERY - 5).Until > 0, "před další událostí ukazuje nulu")
	end)

	--[[
		Střídání je celý smysl: kdyby se vracela pořád ta samá, byla by
		z toho zase jedna událost, jen s delším rozestupem.
	]]
	t.test("události se opravdu střídají", function()
		local seen = {}
		for cycle = 0, #ROTATION - 1 do
			local active = Economy.eventAt(cycle * EVERY).Active
			t.assert(active ~= nil, `cyklus {cycle} nemá událost`)
			t.assert(seen[active.Id] == nil, `{active.Id} přišla dvakrát za sebou v kole`)
			seen[active.Id] = true
		end

		--[[
			A po celém kole se musí vrátit ta první, jinak by se rotace
			postupně rozjížděla s časem.
		]]
		t.equal(
			Economy.eventAt(#ROTATION * EVERY).Active.Id,
			Economy.eventAt(0).Active.Id,
			"rotace se po kole nevrátila na začátek"
		)
	end)

	--[[
		Každá událost musí sahat na jinou část hraní. Kdyby jich pět
		z šesti zvedalo mince, byla by z toho jedna událost s pěti jmény.
	]]
	t.test("každá událost dělá něco jiného", function()
		local fields = { "Coins", "Pickup", "Squeeze", "Smash" }
		local used = {}

		for _, event in ROTATION do
			local mine = nil
			for _, field in fields do
				if event[field] then
					t.assert(mine == nil, `{event.Id} sahá na víc věcí naráz`)
					mine = field
				end
			end

			t.assert(mine ~= nil, `{event.Id} nedělá vůbec nic`)
			t.assert(used[mine] == nil, `{event.Id} dělá to samé co {used[mine]}`)
			used[mine] = event.Id
		end
	end)

	--[[
		Násobek se musí promítnout do peněz, ne jen do nápisu na
		obrazovce. Nápis, za kterým se nic nemění, je horší než žádný.
	]]
	t.test("Payday opravdu znásobí mince", function()
		local profile = {
			Rebirths = 0,
			Passes = {},
			Boosts = {},
			Perks = {},
			Upgrades = {},
		}

		local payday = nil
		for index, event in ROTATION do
			if event.Coins then
				payday = (index - 1) * EVERY
			end
		end
		t.assert(payday ~= nil, "žádná událost nezvedá mince")

		local inside = Economy.coinMultiplier(profile, payday)
		local outside = Economy.coinMultiplier(profile, payday + LENGTH + 10)

		t.assert(inside > outside, "mince se během Payday nezvedly")
	end)
end

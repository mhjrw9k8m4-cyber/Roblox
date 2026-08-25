--!strict
--[[
	Varianty hraček.

	Jedna a ta samá hračka může vyjít obyčejná, zlatá nebo duhová.
	Chyba se tady pozná nejhůř ze všeho: losování je náhodné, takže
	rozbité losování vypadá pořád "nějak" a nikdo nepozná, že zlatá
	nepadá vůbec — nebo naopak že padá pokaždé.

	Proto se losuje z čísla, které dodá volající. Test tak zkouší
	hranice intervalů, ne štěstí.
]]

return function(t)
	local Live = t.require("Live")
	local Economy = t.require("Economy")
	local Config = t.require("Config")

	local NORMAL = 1
	local GOLDEN = 2
	local RAINBOW = 3

	local function profile(fields)
		local base = {
			Coins = 0,
			Gems = 0,
			Power = 0,
			WorldIndex = 1,
			Barrier = 1,
			Rebirths = 0,
			Worlds = { [Config.Worlds[1].Id] = true },
			Upgrades = {},
			Boosts = {},
			Perks = {},
			Passes = {},
			Laps = {},
			Held = {},
			Squishies = {},
			Variants = {},
		}
		for key, value in fields or {} do
			base[key] = value
		end
		return base
	end

	--[[
		Pořadí variant je zároveň pořadím vzácnosti i síly. Kdyby se to
		rozešlo, byla by "vzácnější" varianta slabší a hráč by neměl
		důvod po ní jít.
	]]
	t.test("vzácnější varianta je vždycky silnější", function()
		for index = 2, #Live.Variants do
			local previous = Live.Variants[index - 1]
			local current = Live.Variants[index]

			t.assert(
				current.Chance < previous.Chance,
				`{current.Id} padá častěji než {previous.Id}`
			)
			t.assert(
				current.Multiplier > previous.Multiplier,
				`{current.Id} je vzácnější, ale ne silnější`
			)
		end
	end)

	--[[
		Losuje se z jednoho čísla, takže se dají zkoušet hranice. Duhová
		leží uvnitř zlaté: kdyby to byly dva nezávislé intervaly, vyšla
		by duhová hračka občas "obyčejné" barvy.
	]]
	t.test("losování sedí na hranicích intervalů", function()
		local golden = Live.Variants[GOLDEN].Chance
		local rainbow = Live.Variants[RAINBOW].Chance

		t.equal(Live.rollVariant(0, 0), RAINBOW, "úplně dole nepadla duhová")
		t.equal(Live.rollVariant(0, rainbow * 0.5), RAINBOW, "uvnitř duhového pásma nepadla duhová")
		t.equal(Live.rollVariant(0, rainbow + 1e-6), GOLDEN, "hned za duhovou nepadla zlatá")
		t.equal(Live.rollVariant(0, golden - 1e-6), GOLDEN, "na konci zlatého pásma nepadla zlatá")
		t.equal(Live.rollVariant(0, golden + 1e-6), NORMAL, "za zlatým pásmem nepadla obyčejná")
		t.equal(Live.rollVariant(0, 0.99), NORMAL, "úplně nahoře nepadla obyčejná")
	end)

	--[[
		Luck do teď dělal jen zlaté pickupy. Když má ovlivňovat i tohle,
		musí to být znát — ale ne tak, aby se duhová dala vygrindit na
		jistotu.
	]]
	t.test("štěstí zvedá šanci, ale nedělá z ní jistotu", function()
		local golden = Live.Variants[GOLDEN].Chance

		--[[
			Číslo těsně nad zlatým pásmem: bez štěstí je obyčejná,
			se štěstím musí přeskočit na zlatou.
		]]
		local just_above = golden * 1.5
		t.equal(Live.rollVariant(0, just_above), NORMAL, "bez štěstí to nebyla obyčejná")
		t.equal(Live.rollVariant(0.9, just_above), GOLDEN, "plné štěstí šanci nezvedlo")

		-- I s plným štěstím musí zůstat obyčejné losy
		t.equal(Live.rollVariant(0.9, 0.9), NORMAL, "s plným štěstím padá vzácná varianta pořád")
	end)

	--[[
		Chybějící záznam je obyčejná varianta. Profily z doby před
		variantami tak nepotřebují migraci — a kdyby se to rozešlo,
		spadla by hra každému, kdo hru hrál před updatem.
	]]
	t.test("profil bez variant je celý obyčejný", function()
		local old = profile()
		old.Variants = nil

		t.equal(Live.variantOf(old, "Foam"), NORMAL, "chybějící tabulka nedala obyčejnou")
		t.equal(Live.variantOf(profile(), "Foam"), NORMAL, "prázdná tabulka nedala obyčejnou")
	end)

	--[[
		Varianta musí být znát na výkonu, jinak je to jen barva. Zkouší
		se obě poloviny hračky — držení i mačkání — protože každá se
		počítá jinde a rozejít se můžou nezávisle.
	]]
	t.test("varianta se propíše do držení i do mačkání", function()
		local squishy = nil
		for _, entry in Live.forSale() do
			if entry.Power > 0 and entry.Squeeze > 0 then
				squishy = entry
				break
			end
		end
		t.assert(squishy ~= nil, "žádná hračka se neprodává")

		--[[
			Pozdní svět schválně. V prvním je pickup jedna, takže podíl
			z něj spadne pod jedničku a spodní hranice srovná obyčejnou
			hračku s duhovou — test by procházel i s vypnutými variantami.
		]]
		local late = #Config.Worlds

		local plain = profile({ Held = { squishy.Id }, WorldIndex = late })
		local shiny = profile({
			Held = { squishy.Id },
			WorldIndex = late,
			Variants = { [squishy.Id] = RAINBOW },
		})

		t.assert(
			Economy.squishMultiplier(shiny) > Economy.squishMultiplier(plain),
			"duhová hračka drží stejně jako obyčejná"
		)
		--[[
			Mačkání se musí zvednout **víc**, než o kolik povyskočí pickup.

			Hračka v ruce zvedá i pickup, takže "duhová mačká víc než
			obyčejná" platí i tehdy, když se varianta do mačkání vůbec
			nepropíše — a test by tak neměřil nic. Porovnává se proto
			přírůstek mačkání proti přírůstku pickupu.
		]]
		local pickupGain = Economy.pickupValue(shiny, 0) / Economy.pickupValue(plain, 0)
		local squeezeGain = Economy.squeezeValue(shiny, 0) / Economy.squeezeValue(plain, 0)

		t.assert(
			squeezeGain > pickupGain * 1.5,
			`mačkání povyskočilo {squeezeGain}x, pickup {pickupGain}x — varianta se do mačkání nepropsala`
		)
	end)

	--[[
		Jméno s variantou se ukazuje v panelu, v hlášce po nákupu
		i v obchodu. Obyčejná ho nesmí zaneřádit prázdnou předponou.
	]]
	t.test("jméno nese variantu jen když nějaká je", function()
		t.equal(Live.variantName(NORMAL, "Marshmallow"), "Marshmallow", "obyčejná si přidala předponu")
		t.assert(
			string.find(Live.variantName(RAINBOW, "Marshmallow"), "Marshmallow", 1, true) ~= nil,
			"duhová ztratila jméno hračky"
		)
		t.assert(
			Live.variantName(RAINBOW, "Marshmallow") ~= "Marshmallow",
			"duhová se od obyčejné nepozná"
		)
	end)
end

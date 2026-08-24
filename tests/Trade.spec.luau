--!strict
--[[
	Testy obchodování.

	Obchod je nejčastější díra na duplikaci itemů. Testy tady nekontrolují,
	jestli funguje "šťastná cesta" — to je snadné. Kontrolují ty případy,
	kterými se z obchodu tahají věci zadarmo.
]]

return function(t)
	local Trade = t.require("src/shared/Trade.luau")

	local function inventory(entries)
		return entries
	end

	-- Vkládání do nabídky ---------------------------------------------------

	t.test("nelze nabídnout peta, kterého hráč nevlastní", function()
		local ok = Trade.canAdd(inventory({ Spark = 1 }), {}, "Midas")
		t.equal(ok, false, "cizí pet odmítnut")
	end)

	t.test("nelze nabídnout víc kusů, než hráč má", function()
		-- Klasický pokus: přidat toho samého peta desetkrát
		local pets = inventory({ Spark = 2 })
		local offer = { Spark = 2 }
		local ok = Trade.canAdd(pets, offer, "Spark")
		t.equal(ok, false, "třetí kus odmítnut")
	end)

	t.test("dostupný počet se počítá z inventáře minus nabídka", function()
		t.equal(Trade.available({ Spark = 5 }, { Spark = 2 }, "Spark"), 3, "zbývá tři")
		t.equal(Trade.available({ Spark = 1 }, { Spark = 1 }, "Spark"), 0, "nic nezbývá")
	end)

	t.test("nabídka má strop na počet druhů", function()
		local pets, offer = {}, {}
		for index = 1, Trade.MaxItems do
			local id = "Pet" .. index
			pets[id] = 1
			offer[id] = 1
		end
		pets.Extra = 1

		local ok = Trade.canAdd(pets, offer, "Extra")
		t.equal(ok, false, "sedmý druh odmítnut")

		-- Další kus už nabídnutého druhu ale projít musí
		pets.Pet1 = 2
		local okSame = Trade.canAdd(pets, offer, "Pet1")
		t.equal(okSame, true, "další kus stávajícího druhu projde")
	end)

	-- Ověření v okamžiku výměny -----------------------------------------------

	t.test("nabídka přestane platit, když se inventář mezitím změní", function()
		--[[
			Tohle je hlavní duplikační vektor: hráč nabídne peta, pak ho
			sloučí nebo obchoduje jinde, a kdyby se ověřovalo jen při
			vkládání, výměna by mu ho poslala znovu.
		]]
		local offer = { Comet = 1 }
		local ok = Trade.validate({ Comet = 1 }, offer)
		t.equal(ok, true, "dokud ho má, platí")

		local after = Trade.validate({}, offer)
		t.equal(after, false, "po ztrátě neplatí")
	end)

	t.test("prázdná nabídka neprojde", function()
		local ok = Trade.validate({ Spark = 3 }, {})
		t.equal(ok, false, "jednostranný obchod odmítnut")
	end)

	t.test("záporný nebo nulový počet neprojde", function()
		local ok = Trade.validate({ Spark = 3 }, { Spark = 0 })
		t.equal(ok, false, "nula odmítnuta")
	end)

	-- Samotná výměna ------------------------------------------------------------

	t.test("výměna přesune přesně to, co bylo nabídnuto", function()
		local a, b = Trade.apply({ Spark = 2, Cube = 1 }, { Spark = 1 }, { Midas = 1 }, { Midas = 1 })

		t.equal(a.Spark, 1, "A přišel o jeden Spark")
		t.equal(a.Cube, 1, "nenabídnutý pet zůstal")
		t.equal(a.Midas, 1, "A dostal Midase")
		t.equal(b.Spark, 1, "B dostal Spark")
		t.equal(b.Midas, nil, "B přišel o Midase a záznam zmizel")
	end)

	--[[
		Nejdůležitější test v souboru. Když se tahle vlastnost poruší,
		obchod buď itemy vyrábí, nebo je ničí — a obojí zabije ekonomiku.
	]]
	t.test("výměna nezmění celkový počet kusů", function()
		local invA = { Spark = 3, Cube = 2, Prism = 1 }
		local invB = { Midas = 1, Spark = 1 }
		local offerA = { Spark = 2, Prism = 1 }
		local offerB = { Midas = 1 }

		local before = Trade.totalItems(invA) + Trade.totalItems(invB)
		local a, b = Trade.apply(invA, offerA, invB, offerB)
		local after = Trade.totalItems(a) + Trade.totalItems(b)

		t.equal(after, before, "celkem stejně kusů")
	end)

	t.test("výměna nemění vstupní tabulky", function()
		-- Volající musí mít možnost výsledek zahodit, když ověření selže
		local invA = { Spark = 2 }
		local invB = { Midas = 1 }
		Trade.apply(invA, { Spark = 1 }, invB, { Midas = 1 })

		t.equal(invA.Spark, 2, "vstup A nedotčen")
		t.equal(invB.Midas, 1, "vstup B nedotčen")
	end)

	t.test("výměna stejného petu oběma směry sedí", function()
		local a, b = Trade.apply({ Spark = 3 }, { Spark = 2 }, { Spark = 1 }, { Spark = 1 })
		t.equal(a.Spark, 2, "A: 3 - 2 + 1")
		t.equal(b.Spark, 2, "B: 1 - 1 + 2")
	end)

	-- Nasazení po výměně ------------------------------------------------------------

	t.test("pet daný pryč se sundá z nasazených", function()
		--[[
			Bez tohohle by hráči zůstal v nasazení odkaz na peta, kterého
			už nevlastní, a jeho bonus by se dál počítal — tichá duplikace.
		]]
		local kept = Trade.pruneEquipped({ Cube = 1 }, { "Spark", "Cube" })
		t.equal(#kept, 1, "zůstal jeden")
		t.equal(kept[1], "Cube", "ten, kterého hráč pořád má")
	end)

	t.test("nasazení zůstane, když se nic neztratilo", function()
		local kept = Trade.pruneEquipped({ Spark = 1, Cube = 1 }, { "Spark", "Cube" })
		t.equal(#kept, 2, "oba zůstali")
	end)

	-- Potvrzování --------------------------------------------------------------------

	t.test("změna nabídky ruší obě potvrzení", function()
		--[[
			Klasický podvod: obě strany potvrdí, podvodník na poslední chvíli
			vymění cenného peta za bezcenného. Když jakákoliv změna shodí
			potvrzení, útok přestane fungovat.
		]]
		local session = { ConfirmA = true, ConfirmB = true }
		t.equal(Trade.bothConfirmed(session), true, "obě potvrzena")

		Trade.resetConfirmations(session)
		t.equal(Trade.bothConfirmed(session), false, "po změně nic neplatí")
	end)

	t.test("jedno potvrzení nestačí", function()
		t.equal(Trade.bothConfirmed({ ConfirmA = true, ConfirmB = false }), false, "jen A")
		t.equal(Trade.bothConfirmed({ ConfirmA = false, ConfirmB = true }), false, "jen B")
	end)
end

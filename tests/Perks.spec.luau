--!strict
--[[
	Perky — tokeny se nikde neukládají, dopočítávají se ze zakoupených
	úrovní. Testuje se hlavně to, že se nedají utratit dvakrát a že
	žádná větev nejde koupit dřív, než na ni hráč má.
]]

return function(t)
	local Perks = t.require("Perks")

	local function profile(rebirths: number, perks: any?): any
		return { Rebirths = rebirths, Perks = perks or {} }
	end

	t.test("bez rebirthu nejsou tokeny", function()
		t.equal(Perks.available(profile(0)), 0, "dostupné")
		t.equal(Perks.spent(profile(0)), 0, "utracené")
	end)

	t.test("každý rebirth dá právě jeden token", function()
		t.equal(Perks.available(profile(7)), 7, "sedm rebirthů")
	end)

	--[[
		Nejdůležitější test souboru: kdyby se utracené tokeny počítaly
		odjinud než ze zakoupených úrovní, šlo by je utratit dvakrát.
	]]
	t.test("koupená úroveň token opravdu ubere", function()
		local p = profile(5)
		local before = Perks.available(p)

		local perk = Perks.get("Keep") :: any
		local cost = Perks.cost(perk, 0) :: number
		Perks.apply(p, "Keep")

		t.equal(Perks.available(p), before - cost, "token se neodečetl")
		t.equal(Perks.spent(p), cost, "utracené nesedí")
	end)

	t.test("nedá se koupit víc, než na kolik jsou tokeny", function()
		local p = profile(1)

		t.assert(Perks.canBuy(p, "Keep"), "první úroveň za 1 token neprošla")
		Perks.apply(p, "Keep")

		local allowed, reason = Perks.canBuy(p, "Keep")
		t.assert(not allowed, "druhá úroveň prošla bez tokenu")
		t.equal(reason, "Not enough tokens.", "špatný důvod")
	end)

	t.test("zamčená větev neprojde ani s tokeny", function()
		local rich = profile(100)
		local locked = Perks.get("Rebirth") :: any

		t.assert(locked.Requires > 0, "větev nemá požadavek")
		t.assert(Perks.canBuy(rich, "Rebirth"), "sto rebirthů nestačilo")

		local poor = profile(locked.Requires - 1)
		local allowed = Perks.canBuy(poor, "Rebirth")
		t.assert(not allowed, "zamčená větev prošla")
	end)

	t.test("maximální úroveň se nepřekročí", function()
		local perk = Perks.get("Slot") :: any
		local p = profile(999)

		for _ = 1, perk.MaxLevel do
			t.assert(Perks.canBuy(p, "Slot"), "koupě selhala pod maximem")
			Perks.apply(p, "Slot")
		end

		local allowed, reason = Perks.canBuy(p, "Slot")
		t.assert(not allowed, "šlo přes maximum")
		t.equal(reason, "Max level.", "špatný důvod")
		t.equal(Perks.cost(perk, perk.MaxLevel), nil, "cena nad maximem není nil")
	end)

	t.test("hodnota roste s úrovní", function()
		local perk = Perks.get("Offline") :: any
		local p = profile(50)

		t.equal(Perks.value(p, "Offline"), 0, "nekoupený perk něco dává")
		Perks.apply(p, "Offline")
		t.equal(Perks.value(p, "Offline"), perk.PerLevel, "jedna úroveň")
		Perks.apply(p, "Offline")
		t.equal(Perks.value(p, "Offline"), perk.PerLevel * 2, "dvě úrovně")
	end)

	t.test("neznámý perk nic nedělá", function()
		local p = profile(50)
		t.assert(not Perks.canBuy(p, "vymysleny"), "vymyšlený perk prošel")
		t.equal(Perks.value(p, "vymysleny"), 0, "vymyšlený perk má hodnotu")
		t.equal(Perks.get("vymysleny"), nil, "get vrátil něco")
	end)

	t.test("id jsou jedinečná a ceny pokrývají všechny úrovně", function()
		local seen = {}

		for _, perk in Perks.List do
			t.assert(not seen[perk.Id], `dvakrát id {perk.Id}`)
			seen[perk.Id] = true

			t.assert(perk.MaxLevel > 0, `{perk.Id}: nulové maximum`)
			t.assert(#perk.Cost > 0, `{perk.Id}: prázdný ceník`)
			t.assert(perk.PerLevel > 0, `{perk.Id}: nulový přínos`)

			-- Poslední uvedená cena platí i pro zbylé úrovně, takže ceník
			-- kratší než MaxLevel je v pořádku — prázdný ne.
			for level = 0, perk.MaxLevel - 1 do
				t.assert(Perks.cost(perk, level) ~= nil, `{perk.Id}: chybí cena úrovně {level + 1}`)
			end
		end
	end)

	--[[
		Celý strom musí být dosažitelný, jinak jsou poslední větve
		jen dekorace. Zároveň nesmí jít vykoupit hned — jinak by
		rebirth nebyl volba, ale seznam k odškrtnutí.
	]]
	t.test("celý strom je dosažitelný, ale ne hned", function()
		local total = 0
		local needed = 0

		for _, perk in Perks.List do
			for level = 0, perk.MaxLevel - 1 do
				total += Perks.cost(perk, level) :: number
			end
			needed = math.max(needed, perk.Requires)
		end

		t.assert(total > needed, "celý strom se dá koupit dřív, než se odemkne")
		t.assert(total >= 40, `strom stojí jen {total} tokenů — je moc levný`)
		t.assert(total <= 200, `strom stojí {total} tokenů — nikdo ho nedokoupí`)
	end)
end

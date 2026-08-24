--!strict
--[[
	Testy omezovače volání.

	Nejde tu o podvádění, ale o kvóty: několik handlerů zapisuje do
	DataStore a jeden hráč držící tlačítko by položil ukládání všem.
]]

return function(t)
	local Throttle = t.require("src/shared/Throttle.luau")

	local limit = Throttle.limit(3, 10)

	t.test("první volání projdou až do limitu", function()
		local buckets = {}
		t.equal(Throttle.allow(buckets, "buy", limit, 100), true, "první")
		t.equal(Throttle.allow(buckets, "buy", limit, 100), true, "druhé")
		t.equal(Throttle.allow(buckets, "buy", limit, 100), true, "třetí")
	end)

	t.test("volání nad limit se zablokuje", function()
		local buckets = {}
		for _ = 1, 3 do
			Throttle.allow(buckets, "buy", limit, 100)
		end
		t.equal(Throttle.allow(buckets, "buy", limit, 100), false, "čtvrté odmítnuto")
	end)

	t.test("po vypršení okna se počítá znovu", function()
		local buckets = {}
		for _ = 1, 5 do
			Throttle.allow(buckets, "buy", limit, 100)
		end
		t.equal(Throttle.allow(buckets, "buy", limit, 100), false, "pořád blokováno")
		t.equal(Throttle.allow(buckets, "buy", limit, 110), true, "nové okno")
	end)

	t.test("různé klíče se nepletou", function()
		-- Vyčerpání limitu na nákupy nesmí zablokovat obchodování
		local buckets = {}
		for _ = 1, 5 do
			Throttle.allow(buckets, "buy", limit, 100)
		end
		t.equal(Throttle.allow(buckets, "trade", limit, 100), true, "jiný klíč projde")
	end)

	t.test("zbývající počet sedí", function()
		local buckets = {}
		t.equal(Throttle.remaining(buckets, "buy", limit, 100), 3, "na začátku plný")
		Throttle.allow(buckets, "buy", limit, 100)
		t.equal(Throttle.remaining(buckets, "buy", limit, 100), 2, "po jednom")
		Throttle.allow(buckets, "buy", limit, 100)
		Throttle.allow(buckets, "buy", limit, 100)
		t.equal(Throttle.remaining(buckets, "buy", limit, 100), 0, "vyčerpáno")
	end)

	t.test("zablokované volání nesnižuje zbytek pod nulu", function()
		local buckets = {}
		for _ = 1, 20 do
			Throttle.allow(buckets, "buy", limit, 100)
		end
		t.equal(Throttle.remaining(buckets, "buy", limit, 100), 0, "nikdy záporné")
	end)

	t.test("úklid zahodí jen dávno vypršená okna", function()
		local buckets = {}
		Throttle.allow(buckets, "old", limit, 100)
		Throttle.allow(buckets, "fresh", limit, 118)

		Throttle.prune(buckets, limit, 121)
		t.equal(buckets.old, nil, "staré pryč")
		t.assert(buckets.fresh ~= nil, "čerstvé zůstalo")
	end)
end

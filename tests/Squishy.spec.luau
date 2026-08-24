--!strict
--[[
	Squishy hračky.

	Hračka má dvě čísla a každé dělá něco jiného: `Power` je pasivní
	násobič za držení, `Squeeze` je podíl pickupu za jedno zmáčknutí.
	Testuje se hlavně to, aby si ta dvě čísla neodporovala a aby dražší
	hračka nebyla horší než levnější — obchod, ve kterém je nejdražší
	kus pastí, hráče naučí do obchodu nechodit.
]]

return function(t)
	local Live = t.require("Live")
	local Economy = t.require("Economy")
	local Config = t.require("Config")
	local SquishyService = t.require("SquishyService")

	local function profile(fields: any?): any
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
			Laps = {},
			Passes = {},
			Squishies = {},
			Held = {},
			Squeezes = 0,
		}
		for key, value in fields or {} do
			base[key] = value
		end
		return base
	end

	t.test("dražší hračka není slabší než levnější", function()
		local forSale = Live.forSale()
		table.sort(forSale, function(left, right)
			return left.Price < right.Price
		end)

		for index = 2, #forSale do
			local cheaper, dearer = forSale[index - 1], forSale[index]
			t.assert(
				dearer.Power > cheaper.Power,
				`{dearer.Name} stojí víc než {cheaper.Name}, ale nedává víc Poweru`
			)
		end
	end)

	--[[
		Tvrdá hračka má dávat víc za držení a míň za mačkání. Kdyby šlo
		obojí stejným směrem, není z čeho vybírat a celý rozdíl mezi
		hračkami se scvrkne na jedno číslo.
	]]
	t.test("tvrdší hračka se hůř mačká", function()
		for _, squishy in Live.Squishies do
			t.assert(
				squishy.Softness > 0 and squishy.Softness <= 1,
				`{squishy.Name}: měkkost {squishy.Softness} je mimo rozsah`
			)
			t.assert(
				squishy.Squeeze > 0 and squishy.Squeeze <= 1,
				`{squishy.Name}: síla zmáčknutí {squishy.Squeeze} je mimo rozsah`
			)
		end

		local soft, hard
		for _, squishy in Live.Squishies do
			if squishy.Softness >= 0.95 then
				soft = soft or squishy
			elseif squishy.Softness <= 0.35 then
				hard = hard or squishy
			end
		end

		t.assert(soft ~= nil, "v katalogu není žádná měkká hračka")
		t.assert(hard ~= nil, "v katalogu není žádná tvrdá hračka")
		t.assert(soft.Squeeze > hard.Squeeze, "měkká hračka se nemačká líp než tvrdá")
	end)

	t.test("každá hračka má stupeň, který existuje", function()
		local ids = {}
		for _, squishy in Live.Squishies do
			t.assert(Live.Grades[squishy.Grade] ~= nil, `{squishy.Name}: neznámý stupeň {squishy.Grade}`)
			t.assert(not ids[squishy.Id], `dvakrát id {squishy.Id}`)
			ids[squishy.Id] = true
			t.assert(Live.squishy(squishy.Id) ~= nil, `{squishy.Id} se nedá dohledat`)
		end
	end)

	--[[
		Něco musí jít vydřít, ne koupit. Kdyby se dalo koupit všechno,
		nemá streak ani poslední svět co nabídnout.
	]]
	t.test("část hraček je jen za odměnu", function()
		local sale = #Live.forSale()
		t.assert(sale > 0, "nedá se koupit vůbec nic")
		t.assert(sale < #Live.Squishies, "všechno se dá koupit — odměny nemají co dát")
	end)

	t.test("prázdná ruka nemačká", function()
		t.equal(Economy.squeezeValue(profile(), 0), 0, "bez hračky se dá mačkat")
		t.equal(Economy.squishMultiplier(profile()), 1, "bez hračky je bonus")
	end)

	--[[
		Mačká se to, co je v ruce — tedy PRVNÍ v pořadí. Kdyby se braly
		všechny, byla by nejlepší strategie nabrat si tři slabé místo
		jedné dobré a celá volba by ztratila smysl.
	]]
	t.test("mačká se jen ta v ruce, ne celá sbírka", function()
		local weak, strong
		for _, squishy in Live.Squishies do
			if not weak or squishy.Squeeze < weak.Squeeze then
				weak = squishy
			end
			if not strong or squishy.Squeeze > strong.Squeeze then
				strong = squishy
			end
		end

		local inHand = Economy.squeezeValue(profile({ Held = { strong.Id, weak.Id } }), 0)
		local behind = Economy.squeezeValue(profile({ Held = { weak.Id, strong.Id } }), 0)

		t.assert(inHand > behind, "na pořadí v ruce nezáleží")
	end)

	t.test("pas Iron Grip zdvojnásobí zmáčknutí", function()
		local held = { Live.Squishies[1].Id }
		local plain = Economy.squeezeValue(profile({ Held = held }), 0)
		local gripped = Economy.squeezeValue(profile({ Held = held, Passes = { Grip = true } }), 0)

		t.equal(gripped, plain * Live.PassBonus.Grip, "pas nezvedl sílu zmáčknutí")
	end)

	t.test("VIP a perk přidávají sloty, ne ubírají", function()
		local plain = SquishyService.slots(profile())
		local vip = SquishyService.slots(profile({ Passes = { Vip = true } }))

		t.equal(plain, Live.MaxHeld, "základní počet slotů nesedí")
		t.assert(vip > plain, "VIP nepřidal ani jeden slot")
	end)

	--[[
		Zmáčknutí musí růst s postupem hráče stejně jako pickup. Pevné
		číslo by bylo v první hodině všechno a v desáté nic.
	]]
	t.test("síla zmáčknutí roste s postupem", function()
		local held = { Live.Squishies[1].Id }
		local rookie = Economy.squeezeValue(profile({ Held = held }), 0)
		local veteran = Economy.squeezeValue(profile({ Held = held, Rebirths = 10 }), 0)

		t.assert(veteran > rookie, "zmáčknutí se s rebirthy nezvedlo")
	end)
end

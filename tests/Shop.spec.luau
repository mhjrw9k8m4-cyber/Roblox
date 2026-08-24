--!strict
--[[
	Obchod — denní sleva a směna gemů.

	Obojí počítá server ze svého času a ze svého profilu, takže se
	testuje hlavně to, že klient nemá jak výsledek ovlivnit.
]]

return function(t)
	local Economy = t.require("Economy")
	local Config = t.require("Config")
	local Live = t.require("Live")

	local DAY = 86400

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
			EquippedPets = {},
			Passes = {},
		}
		for key, value in fields or {} do
			base[key] = value
		end
		return base
	end

	t.test("nabídka se točí a každý boost přijde na řadu", function()
		local seen = {}

		for day = 0, #Live.Deal.Rotation - 1 do
			local id = Economy.dealId(day * DAY)
			t.assert(Config.boost(id) ~= nil, `den {day}: neznámý boost {id}`)
			seen[id] = true
		end

		local count = 0
		for _ in seen do
			count += 1
		end
		t.equal(count, #Live.Deal.Rotation, "některý boost se v rotaci nikdy neobjeví")
	end)

	t.test("nabídka je stejná pro všechny a mění se až dalším dnem", function()
		local morning = Economy.dealId(5 * DAY)
		local evening = Economy.dealId(5 * DAY + DAY - 1)
		local tomorrow = Economy.dealId(6 * DAY)

		t.equal(morning, evening, "sleva se změnila uprostřed dne")
		t.assert(morning ~= tomorrow, "sleva se dalším dnem nezměnila")
	end)

	t.test("slevu dostane jen dnešní boost", function()
		local now = 3 * DAY
		local discounted = Economy.dealId(now)

		for _, boost in Config.Boosts do
			local price = Economy.boostPrice(boost.Id, now)

			if boost.Id == discounted then
				t.assert(price < boost.Gems, "dnešní boost nemá slevu")
			else
				t.equal(price, boost.Gems, `{boost.Id} má slevu, i když není v akci`)
			end
		end
	end)

	t.test("sleva nikdy nespadne na nulu", function()
		-- Zaokrouhlení dolů by u levného boostu mohlo dát cenu 0 gemů
		for _, boost in Config.Boosts do
			for day = 0, 9 do
				t.assert(Economy.boostPrice(boost.Id, day * DAY) >= 1, `{boost.Id} zdarma`)
			end
		end
	end)

	t.test("na boost bez gemů to nepustí ani ve slevě", function()
		local now = 0
		local id = Economy.dealId(now)
		local price = Economy.boostPrice(id, now)

		t.assert(not Economy.canBuyBoost(profile({ Gems = price - 1 }), id, now), "prošlo pod cenou")
		t.assert(Economy.canBuyBoost(profile({ Gems = price }), id, now), "neprošlo přesně na ceně")
	end)

	t.test("neznámý boost neprojde", function()
		t.assert(not Economy.canBuyBoost(profile({ Gems = 9999 }), "vymysleny", 0), "vymyšlený boost prošel")
		t.equal(Economy.boostPrice("vymysleny", 0), 0, "vymyšlený boost má cenu")
	end)

	t.test("směna chce plný počet gemů", function()
		t.assert(not Economy.canExchange(profile({ Gems = Live.Exchange.Gems - 1 })), "prošlo pod cenou")
		t.assert(Economy.canExchange(profile({ Gems = Live.Exchange.Gems })), "neprošlo přesně na ceně")
	end)

	--[[
		Kurz je násobek příjmu, ne pevná částka. Kdyby byl pevný, byl by
		po hodině hraní směšný — proto se testuje, že s hráčem opravdu roste.
	]]
	t.test("kurz roste s příjmem hráče", function()
		local weak = profile()
		local strong = profile({ Upgrades = { Power = 30 }, Rebirths = 4 })

		local a = Economy.exchangeValue(weak, 0)
		local b = Economy.exchangeValue(strong, 0)

		t.assert(a > 0, "nováček dostane nulu")
		t.assert(b > a, "silnějšímu hráči kurz nevzrostl")
	end)
end

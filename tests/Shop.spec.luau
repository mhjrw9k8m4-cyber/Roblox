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
	--[[
		Řádka vylepšení musí říct, co hráč má a co dostane.

		Bez toho tam byl jen statický popis ("+2 studs of pickup reach")
		a otázku "vyplatí se mi to?" hráč zodpovědět nemohl — číslo,
		které si kupuje, nikde nebylo vidět.

		Účinek se odvozuje z `PerLevel`, takže se nemůže rozejít s tím,
		co vylepšení doopravdy dělá. Test hlídá právě to odvození:
		každá další úroveň musí říct něco jiného než ta předchozí,
		jinak je popisek jen ozdoba.
	]]
	t.test("každé vylepšení umí říct svůj účinek", function()
		for _, upgrade in Config.Upgrades do
			local zero = Config.upgradeEffect(upgrade.Id, 0)
			local one = Config.upgradeEffect(upgrade.Id, 1)
			local top = Config.upgradeEffect(upgrade.Id, upgrade.MaxLevel)

			t.assert(#zero > 0, `{upgrade.Id}: nultá úroveň nemá popis účinku`)
			t.assert(one ~= zero, `{upgrade.Id}: první úroveň říká totéž co nultá`)
			t.assert(top ~= one, `{upgrade.Id}: poslední úroveň říká totéž co první`)

			t.assert(
				string.match(top, "%+([%d%.]+)") ~= nil,
				`{upgrade.Id}: z popisku "{top}" nejde vyčíst číslo`
			)
		end
	end)

	t.test("vymyšlené vylepšení nemá účinek, ale nespadne", function()
		t.equal(Config.upgradeEffect("vymyslene", 3), "", "neznámé id vrátilo popis")
	end)

	--[[
		Číslo v popisku musí sedět s tím, co vylepšení DOOPRAVDY dělá.

		Očekávané jednotky si drží test sám, ne konfigurace — kdyby je
		bral z `Scale`, porovnával by konfiguraci sama se sebou a
		špatně zvolený `Scale` by prošel. Takhle test říká "Power se
		ukazuje v procentech" a ověří to proti `Economy`, tedy proti
		tomu, co se v ekonomice skutečně spočítá.
	]]
	t.test("popisek účinku sedí s tím, co ekonomika spočítá", function()
		local Economy = t.require("Economy")

		local function base(levels)
			return {
				Coins = 0,
				Gems = 0,
				Power = 0,
				WorldIndex = 1,
				Barrier = 1,
				Rebirths = 0,
				Upgrades = levels,
				Boosts = {},
				Perks = {},
				Passes = {},
				Laps = {},
				Held = {},
				Squishies = {},
			}
		end

		--[[
			Skutečný přírůstek na jedné úrovni a jednotka, ve které ho
			má obchod ukazovat.
		]]
		local CHECKS = {
			{
				--[[
					Přírůstek se měří na tisící úrovni a vydělí tisícem.
					`pickupValue` zaokrouhluje dolů, takže rozdíl jedné
					úrovně by se v zaokrouhlení ztratil; přes tisíc
					úrovní je zaokrouhlení pod rozlišením testu.
				]]
				Id = "Power",
				Unit = 100,
				Gain = function()
					local many = Economy.pickupValue(base({ Power = 1000 }), 0)
					local none = Economy.pickupValue(base({}), 0)
					return (many - none) / none / 1000
				end,
			},
			{
				Id = "Magnet",
				Unit = 1,
				Gain = function()
					return Economy.collectRadius(base({ Magnet = 1 }), nil, 0)
						- Economy.collectRadius(base({}), nil, 0)
				end,
			},
			{
				Id = "Speed",
				Unit = 1,
				Gain = function()
					return Economy.walkSpeed(base({ Speed = 1 }), nil, 0)
						- Economy.walkSpeed(base({}), nil, 0)
				end,
			},
			{
				Id = "Luck",
				Unit = 100,
				Gain = function()
					return Economy.luckChance(base({ Luck = 1 })) - Economy.luckChance(base({}))
				end,
			},
			{
				Id = "Auto",
				Unit = 1,
				Gain = function()
					return Economy.autoRate(base({ Auto = 1 }), 0) - Economy.autoRate(base({}), 0)
				end,
			},
		}

		t.equal(#CHECKS, #Config.Upgrades, "přibylo vylepšení, které tenhle test nezná")

		for _, check in CHECKS do
			local shown = tonumber(string.match(Config.upgradeEffect(check.Id, 1), "%+([%d%.]+)"))
			local expected = check.Gain() * check.Unit

			t.assert(shown ~= nil, `{check.Id}: z popisku nejde vyčíst číslo`)
			t.assert(
				math.abs(shown - expected) < 0.05,
				`{check.Id}: obchod slibuje {shown}, ekonomika dává {expected}`
			)
		end
	end)

end

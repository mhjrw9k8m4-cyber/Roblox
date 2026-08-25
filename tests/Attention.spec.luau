--!strict
--[[
	Techniky, které drží pozornost.

	Dvě věci, u kterých se chyba pozná až tím, že hráč přestane hrát —
	tedy pozdě:

	  * odznak u tlačítka. Říká jen, že tam něco JE, a nic neslibuje
	    navíc; hráč, který o volné truhle neví, si ji nevezme, a odměna,
	    kterou si nikdo nevezme, je stejná jako žádná.
	  * šťastná zeď. Nepravidelná odměna drží pozornost líp než
	    pravidelná — ale jen dokud je opravdu nepravidelná a dokud
	    ekonomiku nepřepíše.
]]

return function(t)
	local Economy = t.require("Economy")
	local Track = t.require("Track")
	local Config = t.require("Config")

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
			NextChestAt = 0,
		}
		for key, value in fields or {} do
			base[key] = value
		end
		return base
	end

	--[[
		Nováček s prázdnou peněženkou nesmí mít rozsvíceno všechno.
		Odznak, který svítí pořád, přestane po minutě něco znamenat
		a hráč ho odnaučí vidět.
	]]
	t.test("nováčkovi svítí jen to, na co opravdu má", function()
		local fresh = profile({ NextChestAt = 1e9 })
		local badges = Economy.badges(fresh, 0)

		t.equal(badges.chest, false, "truhla svítí, i když ještě nedozrála")
		t.equal(badges.upgrades, false, "vylepšení svítí bez jediné mince")
		t.equal(badges.squishies, false, "hračka svítí bez jediné mince")
		t.equal(badges.worlds, false, "další svět svítí bez jediné mince")
		t.equal(badges.rebirth, false, "rebirth svítí hned na startu")
	end)

	t.test("odznak naskočí, jakmile na to hráč má", function()
		local first = Config.Upgrades[1]
		local price = Config.upgradePrice(first.Id, 0)
		t.assert(price ~= nil, "první vylepšení nemá cenu")

		local poor = Economy.badges(profile({ Coins = price - 1, NextChestAt = 1e9 }), 0)
		local rich = Economy.badges(profile({ Coins = price, NextChestAt = 1e9 }), 0)

		t.equal(poor.upgrades, false, "svítí, i když na vylepšení chybí mince")
		t.equal(rich.upgrades, true, "hráč má na vylepšení a nic mu to neřeklo")
	end)

	t.test("dozrálá truhla se ohlásí", function()
		local ready = Economy.badges(profile({ NextChestAt = 100 }), 200)
		local waiting = Economy.badges(profile({ NextChestAt = 300 }), 200)

		t.equal(ready.chest, true, "truhla dozrála a nikdo se to nedozvěděl")
		t.equal(waiting.chest, false, "truhla svítí, přestože se na ni čeká")
	end)

	--[[
		Šťastná zeď musí být nepravidelná, ale nesmí být ani vzácnost,
		o které hráč za sezení neuslyší, ani pravidlo, které si
		odpočítá.
	]]
	t.test("šťastná zeď padá zhruba tak často, jak má", function()
		local TRACK = Config.Track
		local found, total = 0, 0

		for world = 1, #Config.Worlds do
			for lap = 0, 9 do
				for index = 1, TRACK.BarrierCount do
					total += 1
					if Track.isJackpot(world, lap, index) then
						found += 1
					end
				end
			end
		end

		local perMille = found / total * 1000
		t.assert(
			perMille > TRACK.JackpotPerMille * 0.5 and perMille < TRACK.JackpotPerMille * 1.8,
			`{math.floor(perMille)} z tisíce, čekáno kolem {TRACK.JackpotPerMille}`
		)
	end)

	--[[
		Stejná zeď musí vyjít stejně pokaždé. Klient ji ukazuje předem
		("LUCKY WALL") a server ji vyplácí — kdyby se rozešli, slíbila
		by cedule jackpot, který nepřijde.
	]]
	t.test("šťastná zeď je pokaždé ta samá", function()
		for index = 1, Config.Track.BarrierCount do
			t.equal(
				Track.isJackpot(3, 2, index),
				Track.isJackpot(3, 2, index),
				`zeď {index} vychází pokaždé jinak`
			)
		end
	end)

	t.test("jackpot se propíše do odměny za průraz", function()
		local TRACK = Config.Track
		local lucky, plain

		for index = 1, TRACK.BarrierCount do
			if Track.isJackpot(1, 0, index) then
				lucky = lucky or index
			else
				plain = plain or index
			end
		end

		t.assert(lucky ~= nil, "v prvním kole prvního světa není ani jedna šťastná zeď")
		t.assert(plain ~= nil, "v prvním kole prvního světa jsou šťastné všechny")

		--[[
			Porovnává se stejná zeď se sebou, ne dvě různé: pozdější zeď
			platí víc sama o sobě, takže by test procházel i s vypnutým
			jackpotem.
		]]
		local base = profile({ Power = 1e9 })
		local before = Economy.smashReward(base, lucky, 0)

		local original = TRACK.JackpotMultiplier
		TRACK.JackpotMultiplier = 1
		local without = Economy.smashReward(base, lucky, 0)
		TRACK.JackpotMultiplier = original

		t.assert(
			before > without * 2,
			`šťastná zeď platí {before}, obyčejná {without} — jackpot se nepropsal`
		)
	end)

	--[[
		Meta ve spodním pruhu. Musí být vždycky ta nejbližší — cíl,
		o kterém je vidět, že se blíží, je jediný, který táhne.
	]]
	t.test("meta je vždycky ta nejbližší", function()
		local Live = t.require("Live")

		local cheapest = nil
		for _, squishy in Live.forSale() do
			if cheapest == nil or squishy.Price < cheapest.Price then
				cheapest = squishy
			end
		end
		t.assert(cheapest ~= nil, "žádná hračka se neprodává")

		local goal = Economy.nextGoal(profile())
		t.assert(goal ~= nil, "nováček nemá žádnou metu")
		t.equal(goal.Id, cheapest.Id, "meta není nejlevnější nekoupená hračka")
		t.equal(goal.Ready, false, "meta hlásí READY bez jediné mince")

		--[[
			Druhý svět stojí mnohonásobek nejlevnější hračky, takže dokud
			je hračka nekoupená, nesmí ho hra nabízet: byl by to cíl na
			hodiny dopředu místo na minutu.
		]]
		t.equal(goal.Kind, "squishy", "nováčkovi se nabízí svět místo hračky")
	end)

	--[[
		Když hráč na metu má, musí to pruh říct dřív, než odejde jinam.
		Naspořeno a nikde to není vidět je nejhorší z obou světů.
	]]
	t.test("meta se přepne na READY, jakmile na ni hráč má", function()
		local poor = Economy.nextGoal(profile())
		local rich = Economy.nextGoal(profile({ Coins = poor.Price }))

		t.equal(rich.Id, poor.Id, "meta se koupí penězi změnila")
		t.equal(rich.Ready, true, "hráč na metu má a pruh mlčí")
		t.equal(rich.Progress, 1, "pruh není plný, i když je naspořeno")
	end)

	--[[
		Postup nesmí umět přeskočit dopředu ani zpátky: `Progress` se
		nesmí přelít přes jedničku, jinak by pruh přetekl mimo rám.
	]]
	t.test("postup mety se drží v mezích", function()
		local goal = Economy.nextGoal(profile({ Coins = 1e18 }))
		t.assert(goal ~= nil, "boháč nemá žádnou metu")
		t.equal(goal.Progress, 1, `postup {goal.Progress} přetekl přes jedničku`)
	end)

	--[[
		Hráč, který má všechny hračky, musí dostat jako metu další svět —
		ne prázdný pruh. Prázdný pruh po nákupu poslední hračky vypadá
		jako konec hry.
	]]
	t.test("po vykoupení hraček přebírá metu další svět", function()
		local Live = t.require("Live")

		local all = {}
		for _, squishy in Live.forSale() do
			all[squishy.Id] = true
		end

		local goal = Economy.nextGoal(profile({ Squishies = all }))
		t.assert(goal ~= nil, "s vykoupenými hračkami zmizela meta úplně")
		t.equal(goal.Kind, "world", "metou po hračkách není další svět")
		t.equal(goal.Id, Config.Worlds[2].Id, "nabízí se jiný svět než ten hned další")
	end)
end

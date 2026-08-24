--!strict
--[[
	Nálet (surge) — krátké zrychlení po silném průrazu.

	Server ho drží jen v paměti, takže se testuje čistý vzorec: kdy se
	spustí, co mění a hlavně že po vypršení nezůstane nic navíc.
]]

return function(t)
	local Economy = t.require("Economy")
	local Config = t.require("Config")

	local TRACK = Config.Track

	local function profile(fields: any?): any
		local base = {
			Coins = 0, Gems = 0, Power = 0,
			WorldIndex = 1, Barrier = 1, Rebirths = 0,
			Worlds = { [Config.Worlds[1].Id] = true },
			Upgrades = {}, Boosts = {}, Perks = {}, Laps = {},
			EquippedPets = {}, Passes = {},
		}
		for key, value in fields or {} do
			base[key] = value
		end
		return base
	end

	t.test("spouští ho až velké přeplácnutí", function()
		t.assert(not Economy.surgeTriggered(1), "nálet i bez přeplácnutí")
		t.assert(not Economy.surgeTriggered(TRACK.SurgeAt - 0.01), "těsně pod prahem prošel")
		t.assert(Economy.surgeTriggered(TRACK.SurgeAt), "přesně na prahu neprošel")
	end)

	--[[
		Práh musí být nad běžným přeplácnutím, jinak by nálet běžel pořád
		a přestal by být odměnou. Průměr měří simulace (kolem ×8–10).
	]]
	t.test("práh je nad běžným přeplácnutím", function()
		t.assert(TRACK.SurgeAt >= 10, `práh {TRACK.SurgeAt} je moc nízko — nálet by běžel pořád`)
	end)

	t.test("běží jen do svého času", function()
		t.assert(Economy.surgeActive(100, 99), "nálet nezačal")
		t.assert(not Economy.surgeActive(100, 100), "nálet běží i v okamžiku vypršení")
		t.assert(not Economy.surgeActive(100, 101), "nálet běží po vypršení")
		t.assert(not Economy.surgeActive(nil, 50), "nálet běží bez zapnutí")
	end)

	t.test("zrychlí běh a zvětší dosah", function()
		local p = profile()
		local base = Economy.walkSpeed(p)
		local baseRadius = Economy.collectRadius(p)

		local fast = Economy.walkSpeed(p, 100, 50)
		local wide = Economy.collectRadius(p, 100, 50)

		t.assert(fast > base, "rychlost nevzrostla")
		t.assert(wide > baseRadius, "dosah nevzrostl")
		t.equal(fast, base * TRACK.SurgeSpeed, "špatný násobek rychlosti")
		t.equal(wide, baseRadius * TRACK.SurgeRadius, "špatný násobek dosahu")
	end)

	--[[
		Nejdůležitější test souboru: po vypršení se musí obojí vrátit
		přesně na původní hodnotu. Kdyby zůstalo cokoliv navíc, hráč by
		zrychlení držel napořád a stačilo by jednou trefit velký průraz.
	]]
	t.test("po vypršení se vrátí přesně na původní hodnoty", function()
		local p = profile({ Upgrades = { Speed = 7, Magnet = 4 } })

		t.equal(Economy.walkSpeed(p, 100, 200), Economy.walkSpeed(p), "rychlost zůstala zvýšená")
		t.equal(Economy.collectRadius(p, 100, 200), Economy.collectRadius(p), "dosah zůstal zvětšený")
	end)

	t.test("nálet se skládá s upgrady, nenahrazuje je", function()
		local weak = profile()
		local strong = profile({ Upgrades = { Speed = 20 } })

		t.assert(
			Economy.walkSpeed(strong, 100, 50) > Economy.walkSpeed(weak, 100, 50),
			"nálet setřel rozdíl mezi hráči"
		)
	end)

	t.test("délka a násobky dávají smysl", function()
		t.assert(TRACK.SurgeSeconds > 1, "nálet je moc krátký na to, aby se stihl projevit")
		t.assert(TRACK.SurgeSeconds <= 8, "nálet je tak dlouhý, že přestává být událostí")
		t.assert(TRACK.SurgeSpeed > 1 and TRACK.SurgeSpeed < 2, "násobek rychlosti mimo rozsah")
		t.assert(TRACK.SurgeRadius > 1 and TRACK.SurgeRadius < 3, "násobek dosahu mimo rozsah")
	end)
end

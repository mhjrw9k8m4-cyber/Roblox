--!strict
--[[
	Dvojnásobek pro celý server.

	Okno se počítá z času, ne ze stavu — nic se neukládá a nic
	nereplikuje, takže na něm klient i server nezávisle vyjdou stejně.
	Testuje se hlavně to, že se ta dvě čísla (jak často, jak dlouho)
	nedají nastavit tak, aby okno buď nikdy neskončilo, nebo nikdy
	nezačalo.
]]

return function(t)
	local Economy = t.require("Economy")
	local Live = t.require("Live")

	local EVERY = Live.Happy.EverySeconds
	local LENGTH = Live.Happy.LengthSeconds

	t.test("okno je kratší než rozestup", function()
		t.assert(LENGTH > 0, "okno má nulovou délku, nikdy nezačne")
		t.assert(
			LENGTH < EVERY,
			`okno trvá {LENGTH} s a opakuje se po {EVERY} s — nikdy by neskončilo`
		)
	end)

	t.test("okno začíná na začátku rozestupu a končí po své délce", function()
		t.equal(Economy.happyMultiplier(0), Live.Happy.Coins, "na začátku okno neběží")
		t.equal(Economy.happyMultiplier(LENGTH - 1), Live.Happy.Coins, "těsně před koncem už neběží")
		t.equal(Economy.happyMultiplier(LENGTH), 1, "okno neskončilo, když mělo")
		t.equal(Economy.happyMultiplier(EVERY - 1), 1, "těsně před dalším oknem už běží")
		t.equal(Economy.happyMultiplier(EVERY), Live.Happy.Coins, "další okno nezačalo")
	end)

	--[[
		Odpočet musí ubývat a skončit na nule. Kdyby ubýval jinak, než
		jak okno doopravdy padá, hráč by viděl na pruhu jiný čas, než
		kolik mu doopravdy zbývá.
	]]
	t.test("odpočet ubývá a mimo okno je nula", function()
		t.equal(Economy.happyRemaining(0), LENGTH, "na začátku nesedí celá délka")
		t.equal(Economy.happyRemaining(LENGTH - 10), 10, "odpočet neubývá po sekundách")
		t.equal(Economy.happyRemaining(LENGTH), 0, "po konci okna zbývá čas")
		t.equal(Economy.happyRemaining(EVERY - 5), 0, "před dalším oknem už něco zbývá")
	end)

	--[[
		Okno se musí promítnout do mincí, ne jen do pruhu na obrazovce.
		Nápis "×2 COINS", za kterým se nic nemění, je horší než žádný.
	]]
	t.test("okno opravdu zdvojnásobí mince", function()
		local profile = {
			Rebirths = 0,
			Passes = {},
			Boosts = {},
			Perks = {},
			Upgrades = {},
		}

		local inside = Economy.coinMultiplier(profile, 0)
		local outside = Economy.coinMultiplier(profile, LENGTH + 10)

		t.equal(inside / outside, Live.Happy.Coins, "mince se během okna nezdvojnásobily")
	end)
end

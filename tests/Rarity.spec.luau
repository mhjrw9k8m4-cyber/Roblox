--!strict
--[[
	Stupnice vzácnosti.

	Vzácnost se počítá z pořadí v žebříčku, ne z ručního štítku
	v datech. Chyba se tady projeví tak, že je celý obsah "Common"
	nebo naopak všechno "Mythic" — což vypadá jako záměr, dokud si
	někdo neprojde celý panel.

	Testuje se proto na obou koncích řady a na tom, že se stupně
	po cestě nevracejí zpátky.
]]

return function(t)
	local Rarity = t.require("Rarity")
	local Config = t.require("Config")
	local Live = t.require("Live")
	local Perks = t.require("Perks")
	local Cosmetics = t.require("Cosmetics")

	--[[
		Kraje řady. První věc ve hře musí být ta nejběžnější a poslední
		ta nejvzácnější — bez toho stupnice nic neměří.
	]]
	t.test("žebříček začíná dole a končí nahoře", function()
		t.equal(Rarity.byRank(1, 10).Id, "Common", "první z deseti není Common")
		t.equal(Rarity.byRank(10, 10).Id, "Mythic", "poslední z deseti není Mythic")

		-- I když je položka jediná, musí z toho něco vyjít
		t.equal(Rarity.byRank(1, 1).Id, "Mythic", "jediná položka nevyšla nahoře")

		-- Nesmyslné vstupy nesmí spadnout ani vyskočit mimo tabulku
		t.equal(Rarity.byRank(99, 10).Id, "Mythic", "pořadí za koncem přeteklo")
		t.equal(Rarity.byRank(0, 10).Id, "Common", "nulté pořadí podteklo")
		t.equal(Rarity.byRank(1, 0).Id, "Common", "prázdný žebříček spadl")
	end)

	--[[
		Stupeň nesmí po cestě klesnout. Kdyby ano, byl by uprostřed hry
		vzácnější kus než na konci — a hráč by neměl důvod jít dál.
	]]
	t.test("stupně po žebříčku jenom rostou", function()
		local previous = 0
		for rank = 1, 40 do
			local order = Rarity.byRank(rank, 40).Order
			t.assert(order >= previous, `pořadí {rank} kleslo z {previous} na {order}`)
			previous = order
		end
	end)

	--[[
		Ohodnocený musí být VŠECHEN obsah. Kus bez stupně by v panelu
		zůstal bez rámečku a vypadal by jako chyba vykreslování.
	]]
	t.test("každý kus obsahu má stupeň", function()
		for index in Config.Worlds do
			t.assert(Config.worldRarity(index) ~= nil, `svět {index} nemá stupeň`)
		end
		for _, upgrade in Config.Upgrades do
			t.assert(Config.upgradeRarity(upgrade.Id) ~= nil, `{upgrade.Id} nemá stupeň`)
		end
		for _, boost in Config.Boosts do
			t.assert(Config.boostRarity(boost.Id) ~= nil, `{boost.Id} nemá stupeň`)
		end
		for _, title in Config.Titles do
			t.assert(Config.titleRarity(title.Id) ~= nil, `{title.Id} nemá stupeň`)
		end
		for _, squishy in Live.Squishies do
			t.assert(Live.squishyRarity(squishy.Id) ~= nil, `{squishy.Id} nemá stupeň`)
		end
		for _, perk in Perks.List do
			t.assert(Perks.rarity(perk.Id) ~= nil, `{perk.Id} nemá stupeň`)
		end
	end)

	--[[
		Světy jsou ta nejviditelnější řada ve hře: první svět musí být
		běžný, poslední mýtický. Kdyby to bylo naopak nebo ploché,
		poznal by to hráč hned v prvním panelu.
	]]
	t.test("první svět je běžný, poslední mýtický", function()
		t.equal(Config.worldRarity(1).Id, "Common", "Glass Hall není Common")
		t.equal(Config.worldRarity(#Config.Worlds).Id, "Mythic", "poslední svět není Mythic")
		t.assert(
			Config.worldRarity(#Config.Worlds).Order > Config.worldRarity(1).Order,
			"stupeň světů neroste"
		)
	end)

	--[[
		Hračky se řadí podle síly, ne podle ceny. Odměnové hračky stojí
		nula, takže v cenovém žebříčku by spadly úplně dolů — a Void
		Core, který se dá získat jedině dohráním, by vyšel jako
		nejběžnější věc ve hře.
	]]
	t.test("odměna za dohrání není nejběžnější hračka", function()
		local final = Live.squishyRarity(Live.FinalReward)
		local starter = Live.squishyRarity(Live.Starter)

		t.equal(final.Id, "Mythic", `{Live.FinalReward} vyšel jako {final.Id}`)
		t.equal(starter.Id, "Common", `{Live.Starter} vyšel jako {starter.Id}`)

		--[[
			Kontrola, že se opravdu řadí, a ne že se jen bere pořadí
			v katalogu: `Lucky Star` je v seznamu až za `Chrome Ball`,
			ale je slabší — takže musí vyjít níž.
		]]
		local star = Live.squishyRarity("Star")
		local ball = Live.squishyRarity("Ball")
		t.assert(
			star.Order < ball.Order,
			`Lucky Star vyšel jako {star.Id}, Chrome Ball jako {ball.Id} — žebříček se neseřadil`
		)
	end)

	--[[
		Kosmetika si vzácnost drží ručně v datech, protože žádný
		žebříček nemá. Musí ale používat ta samá jména jako zbytek hry —
		jinak by "Epic" stopa neměla barvu.
	]]
	t.test("kosmetika používá jména ze společné stupnice", function()
		local known = {}
		for _, tier in Rarity.List do
			known[tier.Id] = true
		end

		for _, kind in Cosmetics.Kinds do
			for _, item in Cosmetics.list(kind) do
				t.assert(
					known[item.Rarity] == true,
					`{kind} {item.Id} má stupeň "{item.Rarity}", který ve stupnici není`
				)
			end
		end
	end)
end

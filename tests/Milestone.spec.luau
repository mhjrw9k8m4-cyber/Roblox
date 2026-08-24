--!nocheck
--[[
	Hlášení velkých okamžiků.

	Modul má jedinou netriviální vlastnost: co se hlásit MÁ a co NE.
	Kdyby filtr povolil moc, výpis se na plném serveru zahltí a hráč
	ho přestane číst — a tím zmizí celý důvod, proč tam je.

	Testuje se přes odchycený `FireAllClients`, takže se ověřuje to, co
	skutečně odletí ke klientům, ne to, co si modul myslí.
]]

return function(t)
	local Remotes = t.require("Remotes")
	local MilestoneService = t.require("MilestoneService")
	local Config = t.require("Config")
	local Live = t.require("Live")

	local sent = {}

	-- Odchycení musí sedět na stejné instanci, jakou používá služba
	Remotes.Milestone.FireAllClients = function(_self, payload)
		table.insert(sent, payload)
	end

	local function fresh()
		table.clear(sent)
	end

	local player = { UserId = 42, DisplayName = "Tester" }

	t.test("rebirth se hlásí a nese číslo v obou textech", function()
		fresh()
		MilestoneService.rebirth(player, 7)

		t.equal(#sent, 1, "rebirth se nehlásil")
		t.equal(sent[1].Kind, "rebirth", "špatný druh")
		t.equal(sent[1].UserId, 42, "chybí UserId, klient nepozná vlastní okamžik")
		t.assert(string.find(sent[1].Big, "7") ~= nil, "nápis neobsahuje číslo rebirthu")
		t.assert(string.find(sent[1].Text, "7") ~= nil, "proužek neobsahuje číslo rebirthu")
	end)

	t.test("první svět se nehlásí, další ano", function()
		fresh()
		MilestoneService.world(player, Config.Worlds[1], 1)
		t.equal(#sent, 0, "svět zdarma se hlásí — spam při každém příchodu")

		MilestoneService.world(player, Config.Worlds[2], 2)
		t.equal(#sent, 1, "koupený svět se nehlásí")
		t.assert(
			string.find(sent[1].Big, string.upper(Config.Worlds[2].Name), 1, true) ~= nil,
			"nápis neobsahuje jméno světa"
		)
	end)

	t.test("běžný pet se nehlásí, vzácný ano", function()
		local common, rare
		for _, rarity in Live.Rarities do
			if rarity.Weight > 10 then
				common = common or rarity
			else
				rare = rare or rarity
			end
		end

		t.assert(common ~= nil, "v konfiguraci není žádná běžná vzácnost")
		t.assert(rare ~= nil, "v konfiguraci není žádná vzácná vzácnost")

		local pet = { Name = "Kostka" }

		fresh()
		MilestoneService.pet(player, pet, common)
		t.equal(#sent, 0, `{common.Name} se hlásí, i když padá běžně`)

		MilestoneService.pet(player, pet, rare)
		t.equal(#sent, 1, `{rare.Name} se nehlásí, i když je vzácný`)
		t.equal(sent[1].Kind, "pet", "špatný druh")
	end)

	--[[
		Vzácný pet schválně `Big` nemá: jeho okamžik je animace líhnutí.
		Klient podle toho pozná, že obřad pouštět nemá — kdyby se to
		nedodrželo, hráč dostane sloup světla přes hlavu úplně zbytečně.
	]]
	t.test("obřad dostane jen to, co má co ukázat", function()
		fresh()
		MilestoneService.rebirth(player, 1)
		MilestoneService.world(player, Config.Worlds[2], 2)

		for _, payload in sent do
			t.assert(payload.Big ~= nil, `{payload.Kind} nemá nápis přes obrazovku`)
		end

		fresh()
		for _, rarity in Live.Rarities do
			if rarity.Weight <= 10 then
				MilestoneService.pet(player, { Name = "Kostka" }, rarity)
			end
		end

		t.assert(#sent > 0, "žádný vzácný pet se neohlásil")
		for _, payload in sent do
			t.equal(payload.Big, nil, "pet by spustil obřad přes animaci líhnutí")
		end
	end)
end

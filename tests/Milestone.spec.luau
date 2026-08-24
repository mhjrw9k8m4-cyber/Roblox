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

	t.test("levná hračka se nehlásí, drahá ano", function()
		local cheap, fancy
		for _, squishy in Live.Squishies do
			local grade = Live.Grades[squishy.Grade]
			if grade.Order < 4 then
				cheap = cheap or squishy
			else
				fancy = fancy or squishy
			end
		end

		t.assert(cheap ~= nil, "v konfiguraci není žádná levná hračka")
		t.assert(fancy ~= nil, "v konfiguraci není žádná drahá hračka")

		fresh()
		MilestoneService.squishy(player, cheap)
		t.equal(#sent, 0, `{cheap.Name} se hlásí, i když ji má za hodinu každý`)

		MilestoneService.squishy(player, fancy)
		t.equal(#sent, 1, `{fancy.Name} se nehlásí, i když je to vrchol sbírky`)
		t.equal(sent[1].Kind, "squishy", "špatný druh")
	end)

	--[[
		Drahá hračka schválně `Big` nemá: obřad přes celou obrazovku
		patří rebirthu a odemčenému světu. Kdyby ho měla i hračka,
		zlevní se tím obojí.
	]]
	t.test("obřad dostane jen to, co má co ukázat", function()
		fresh()
		MilestoneService.rebirth(player, 1)
		MilestoneService.world(player, Config.Worlds[2], 2)

		for _, payload in sent do
			t.assert(payload.Big ~= nil, `{payload.Kind} nemá nápis přes obrazovku`)
		end

		fresh()
		for _, squishy in Live.Squishies do
			MilestoneService.squishy(player, squishy)
		end

		t.assert(#sent > 0, "žádná hračka se neohlásila")
		for _, payload in sent do
			t.equal(payload.Big, nil, "hračka by spustila obřad přes celou obrazovku")
		end
	end)
end

--!strict
--[[
	Nákupní desky na trati.

	Deska se streamingem k hráči doputuje až ve chvíli, kdy k ní dojde
	— ne při startu. Chyba se proto pozná jediným způsobem: hráč dojde
	k desce a na ceduli je text ze serveru, bez úrovně a bez ceny. Než
	si toho někdo všimne, přepíše se to při první změně profilu, takže
	to vypadá jako blikání, ne jako chyba.

	Test proto přidává desku **až po** tom, co profil dorazí — což je
	přesně to pořadí, ve kterém se to ve hře děje.
]]

return function(t)
	local Pads = t.require("Pads")
	local Config = t.require("Config")

	local CollectionService = t.stub().service("CollectionService")
	local RunService = t.stub().service("RunService")

	local PLACEHOLDER = "ze serveru"

	--[[
		Deska tak, jak ji staví server: díl s atributem, billboard
		a popisek. Kdyby se struktura v `WorldService` změnila, tenhle
		test spadne — a to je správně, protože pak přestane fungovat
		i překreslování.
	]]
	local function makePad(upgradeId: string): (any, any)
		local pad = Instance.new("Part")
		pad.Name = `Pad {upgradeId}`
		pad:SetAttribute("Upgrade", upgradeId)
		pad.Parent = workspace

		local billboard = Instance.new("BillboardGui")
		billboard.Name = "Info"
		billboard.Parent = pad

		local label = Instance.new("TextLabel")
		label.Name = "PadText"
		label.Text = PLACEHOLDER
		label.Parent = billboard

		return pad, label
	end

	local started = false
	local function boot()
		if started then
			return
		end
		started = true
		Pads.setBuy(function() end)
		Pads.setWorld(function() end)
		Pads.start()
	end

	t.test("deska, která dorazí po profilu, se přepíše", function()
		boot()

		local upgrade = Config.Upgrades[1]
		Pads.setProfile({ Coins = 0, Upgrades = {}, Worlds = {} })

		local pad, label = makePad(upgrade.Id)
		CollectionService:AddTag(pad, "BuyPad")

		t.equal(label.Text, PLACEHOLDER, "cedule se přepsala dřív, než měla")

		RunService.Heartbeat:Fire(1 / 60)

		t.assert(label.Text ~= PLACEHOLDER, "cedule zůstala s textem ze serveru")
		t.assert(
			string.find(label.Text, string.upper(upgrade.Name), 1, true) ~= nil,
			`na ceduli není jméno vylepšení: {label.Text}`
		)
	end)

	--[[
		Cena, na kterou hráč nemá, musí být poznat barvou. Bez toho stojí
		hráč na desce, nic se neděje a on nemá jak zjistit proč.
	]]
	t.test("nedostupná cena je červená, dostupná ne", function()
		boot()

		local upgrade = Config.Upgrades[1]
		local price = Config.upgradePrice(upgrade.Id, 0)
		t.assert(price ~= nil, "první vylepšení nemá cenu")

		local pad, label = makePad(upgrade.Id)
		CollectionService:AddTag(pad, "BuyPad")

		Pads.setProfile({ Coins = 0, Upgrades = {}, Worlds = {} })
		local poor = label.TextColor3

		Pads.setProfile({ Coins = price, Upgrades = {}, Worlds = {} })
		local rich = label.TextColor3

		t.assert(poor ~= rich, "cedule vypadá stejně, ať na ni hráč má nebo ne")
		t.equal(poor, Config.Theme.Danger, "nedostupná cena není červená")
	end)
end

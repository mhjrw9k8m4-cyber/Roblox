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

	--[[
		Brána do dalšího světa, jak ji staví server: deska s atributem
		a cedule na bláně vedle ní.
	]]
	local function makePortal(worldId: string): (any, any)
		local folder = Instance.new("Folder")
		folder.Parent = workspace

		local pad = Instance.new("Part")
		pad.Name = "Brána světa"
		pad:SetAttribute("World", worldId)
		pad.Parent = folder

		local veil = Instance.new("Part")
		veil.Name = "Blána brány"
		veil.Parent = folder

		local billboard = Instance.new("BillboardGui")
		billboard.Name = "Info"
		billboard.Parent = veil

		local label = Instance.new("TextLabel")
		label.Name = "PortalText"
		label.Text = PLACEHOLDER
		label.Parent = billboard

		return pad, label
	end

	--[[
		Cena bez postupu je u zamčené brány osmiciferné číslo, které nic
		neříká: hráč u ní stojí, nemá na ni a nemá jak poznat, jestli je
		to na pět minut nebo na hodinu.
	]]
	t.test("zamčená brána ukazuje postup, ne jen cenu", function()
		boot()

		local target = Config.Worlds[2]
		local pad, label = makePortal(target.Id)
		CollectionService:AddTag(pad, "WorldPortal")

		Pads.setProfile({
			Coins = target.Price / 4,
			Upgrades = {},
			Worlds = { [Config.Worlds[1].Id] = true },
			WorldIndex = 1,
		})

		t.assert(
			string.find(label.Text, "25%", 1, true) ~= nil,
			`na ceduli není postup: {label.Text}`
		)
		t.assert(
			string.find(label.Text, "PICKUPS", 1, true) ~= nil,
			`na ceduli není, co svět dává: {label.Text}`
		)
		t.equal(label.TextColor3, Config.Theme.Danger, "nedostupná brána není červená")
	end)

	--[[
		Naspořeno a nikde to není vidět je nejhorší z obou možností —
		hráč projde kolem brány, na kterou má.
	]]
	t.test("brána, na kterou hráč má, to řekne", function()
		boot()

		local target = Config.Worlds[2]
		local pad, label = makePortal(target.Id)
		CollectionService:AddTag(pad, "WorldPortal")

		Pads.setProfile({
			Coins = target.Price,
			Upgrades = {},
			Worlds = { [Config.Worlds[1].Id] = true },
			WorldIndex = 1,
		})

		t.assert(
			string.find(label.Text, "READY", 1, true) ~= nil,
			`brána mlčí, i když na ni hráč má: {label.Text}`
		)
		t.equal(label.TextColor3, Config.Theme.Gold, "dostupná brána není zlatá")
	end)

	--[[
		Koupený svět už není nabídka, je to průchod. Cena na ceduli, za
		kterou se znovu neplatí, by mátla.
	]]
	t.test("koupená brána zve dovnitř", function()
		boot()

		local target = Config.Worlds[2]
		local pad, label = makePortal(target.Id)
		CollectionService:AddTag(pad, "WorldPortal")

		Pads.setProfile({
			Coins = 0,
			Upgrades = {},
			Worlds = { [Config.Worlds[1].Id] = true, [target.Id] = true },
			WorldIndex = 1,
		})

		t.assert(
			string.find(label.Text, "ENTER", 1, true) ~= nil,
			`koupená brána neříká ENTER: {label.Text}`
		)
		t.assert(
			string.find(label.Text, "💰", 1, true) == nil,
			`koupená brána pořád ukazuje cenu: {label.Text}`
		)
	end)
end

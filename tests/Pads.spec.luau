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
		-- Daleko od hráče: tenhle test zkouší cedule, ne stoupnutí
		pad.Position = Vector3.new(500, 0, 0)
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

	--[[
		Truhla na placu tak, jak ji staví server: tělo se značkou,
		světelný pás vedle něj a cedule s odpočtem.
	]]
	local function makeChest(position: any): (any, any, any)
		local folder = Instance.new("Folder")
		folder.Parent = workspace

		local body = Instance.new("Part")
		body.Name = "Truhla"
		body.Position = position or Vector3.new(0, 0, -500)
		body.Parent = folder

		local glow = Instance.new("Part")
		glow.Name = "Světlo truhly"
		glow.Parent = folder

		local billboard = Instance.new("BillboardGui")
		billboard.Name = "Info"
		billboard.Parent = body

		local label = Instance.new("TextLabel")
		label.Name = "ChestText"
		label.Text = PLACEHOLDER
		label.Parent = billboard

		return body, label, glow
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
		pad.Position = Vector3.new(0, 0, 500)
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

	--[[
		Odpočet je jediná věc na trati, která se mění bez zásahu hráče.
		Musí se překreslovat i ve chvíli, kdy hráč jen stojí — zamrzlý
		odpočet vypadá jako rozbitá hra.
	]]
	t.test("odpočet na truhle běží i bez změny profilu", function()
		boot()

		local body, label = makeChest()
		CollectionService:AddTag(body, "ChestPad")

		Pads.setProfile({
			Coins = 0,
			Upgrades = {},
			Worlds = {},
			WorldIndex = 1,
			ServerTime = os.time(),
			NextChestAt = os.time() + 600,
		})

		local first = label.Text
		t.assert(first ~= PLACEHOLDER, "cedule zůstala s textem ze serveru")

		--[[
			Profil se mezitím nehne — mění se jen čas. Bez vlastního
			tempa v Heartbeatu by cedule zůstala na první hodnotě.
		]]
		Pads.setProfile({
			Coins = 0,
			Upgrades = {},
			Worlds = {},
			WorldIndex = 1,
			ServerTime = os.time() + 60,
			NextChestAt = os.time() + 600,
		})

		t.assert(label.Text ~= first, `odpočet zamrzl na "{label.Text}"`)
	end)

	--[[
		Zlatá truhla po celou dobu čekání by hráče naučila, že zlatá nic
		neznamená — a v tu chvíli přestane fungovat i ta odemčená.
	]]
	t.test("nedozrálá truhla je šedá, hotová zlatá", function()
		boot()

		local body, label, glow = makeChest()
		CollectionService:AddTag(body, "ChestPad")

		Pads.setProfile({
			Coins = 0,
			Upgrades = {},
			Worlds = {},
			WorldIndex = 1,
			ServerTime = os.time(),
			NextChestAt = os.time() + 600,
		})
		local waiting = body.Color
		t.assert(
			string.find(label.Text, "STEP ON IT", 1, true) == nil,
			`nedozrálá truhla zve dovnitř: {label.Text}`
		)

		Pads.setProfile({
			Coins = 0,
			Upgrades = {},
			Worlds = {},
			WorldIndex = 1,
			ServerTime = os.time(),
			NextChestAt = os.time() - 1,
		})

		t.assert(waiting ~= body.Color, "truhla vypadá stejně čekající i hotová")
		t.equal(body.Color, Config.Theme.Gold, "hotová truhla není zlatá")
		t.equal(glow.Color, Config.Theme.Gold, "světlo pod hotovou truhlou nesvítí zlatě")
		t.assert(
			string.find(label.Text, "STEP ON IT", 1, true) ~= nil,
			`hotová truhla neříká, co s ní: {label.Text}`
		)
	end)

	--[[
		Stoupnutí na nedozrálou truhlu nesmí nic poslat. Server by to
		odmítl, ale hráč by za jedno stoupnutí dostal salvu hlášek.
	]]
	t.test("na nedozrálou truhlu se nešlape", function()
		boot()

		local claims = 0
		Pads.setChest(function()
			claims += 1
		end)

		local body = makeChest(Vector3.new(0, 0, 0))
		CollectionService:AddTag(body, "ChestPad")

		local character = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Position = Vector3.new(0, 0, 1)
		root.Parent = character
		character.Parent = workspace
		game:GetService("Players").LocalPlayer.Character = character

		--[[
			Časy se odvozují z jednoho odečtu hodin.

			`os.time()` se během testu překlopí do další vteřiny a dva
			zvlášť počítané "před chvílí" pak vyjdou stejně — test by
			padal jednou za čas a vypadal by jako chyba ve hře.
		]]
		local base = os.time()

		local function push(nextChestAt: number)
			Pads.setProfile({
				Coins = 0,
				Upgrades = {},
				Worlds = {},
				WorldIndex = 1,
				ServerTime = base,
				NextChestAt = nextChestAt,
			})
		end

		push(base + 600)
		RunService.Heartbeat:Fire(1 / 60)
		t.equal(claims, 0, "nedozrálá truhla se pokusila vyzvednout")

		push(base - 1)
		RunService.Heartbeat:Fire(1 / 60)
		t.equal(claims, 1, "hotová truhla se nevyzvedla")

		--[[
			Odpověď serveru ještě nedorazila, takže `NextChestAt` pořád
			ukazuje do minulosti a hráč pořád stojí na truhle.

			Čeká se přes pauzu mezi nákupy: ta drží jen zlomek vteřiny
			a bez čekání by test procházel i bez zámku — tedy by neměřil
			nic.
		]]
		local until_ = os.clock() + 0.5
		while os.clock() < until_ do
		end

		RunService.Heartbeat:Fire(1 / 60)
		t.equal(claims, 1, "truhla se vyzvedla dvakrát za jedno stoupnutí")

		--[[
			Až se ozve server s novým časem, smí se šlapat zas — jinak by
			druhá truhla za sezení nešla vzít vůbec.
		]]
		push(base - 2)
		RunService.Heartbeat:Fire(1 / 60)
		t.equal(claims, 2, "po odpovědi serveru se truhla vzít nedá")

		game:GetService("Players").LocalPlayer.Character = nil
	end)
end

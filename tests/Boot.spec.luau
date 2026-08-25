--!nocheck
--[[
	Startovací test.

	Vznikl proto, že v projektu několik kol seděla chyba, kvůli které hra
	nemohla naběhnout — osm remotů se používalo, ale nebylo definováno —
	a build byl celou dobu zelený. Kompilace u dynamického jazyka
	kontroluje míň, než to vypadá.

	Tenhle test načte celý strom modulů a nastartuje server proti náhradě
	Roblox prostředí. Nekontroluje, že hra je *správně* — na to je zbytek
	testů. Kontroluje, že vůbec *proběhne*, což je jiná a překvapivě
	snadno porušitelná vlastnost.
]]

return function(t)
	-- Načtení modulů -------------------------------------------------------

	local SHARED = {
		"Config", "Live", "Economy", "Format", "Remotes",
		"Build", "Track", "Lock", "Trade", "Throttle", "Assets", "Cosmetics",
		"Combo", "Perks",
	}

	for _, name in SHARED do
		t.test(`modul {name} se načte`, function()
			local module = t.require(name)
			t.assert(module ~= nil, "modul vrátil nil")
		end)
	end

	--[[
		Služby se startují přes `start()`. `WorldService` je výjimka:
		staví svět jednorázově přes `build()` a nic průběžně nedělá.
	]]
	local SERVICES = {
		DataService = "start",
		WorldService = "build",
		GameService = "start",
		ShopService = "start",
		SquishyService = "start",
		RetentionService = "start",
		LeaderboardService = "start",
		MonetizationService = "start",
		PlayerService = "start",
		EventService = "start",
		TradeService = "start",
		AnalyticsService = "start",
		GuardService = "start",
		CosmeticService = "start",
	}

	for name, entry in SERVICES do
		t.test(`služba {name} se načte`, function()
			local service = t.require(name)
			t.assert(service ~= nil, "služba vrátila nil")
			t.assert(typeof(service[entry]) == "function", `služba nemá {entry}()`)
		end)
	end

	--[[
		Klient se do teď netestoval vůbec.

		Bylo to vidět dvakrát: jednou se používal modul bez `require`
		a lint mlčel, podruhé volal klient metodu, kterou náhrada
		Robloxu neměla. Obojí by spadlo až ve Studiu, a to u kódu,
		který běží každému hráči.

		Test dělá dvě věci: načte každý klientský modul a u těch, co
		mají `start()`, ho zavolá. Nekontroluje, že klient je
		*správně* — kontroluje, že vůbec **naběhne**, a to je jiná
		a překvapivě snadno porušitelná vlastnost.
	]]
	local CLIENT = {
		"Squish", "SoundKit", "Textures", "CameraFX", "CharacterFX",
		"CosmeticFX", "Effects", "Fracture", "Held", "Milestone",
		"Onboarding", "Pads", "TrackView",
	}

	for _, name in CLIENT do
		t.test(`klientský modul {name} se načte`, function()
			local module = t.require(name)
			t.assert(module ~= nil, "modul vrátil nil")
		end)
	end

	local CLIENT_START = { "Squish", "Textures", "CameraFX", "Held", "Pads" }

	for _, name in CLIENT_START do
		t.test(`klientský modul {name} nastartuje`, function()
			local module = t.require(name)
			t.assert(typeof(module.start) == "function", "modul nemá start()")
			module.start()
		end)
	end

	--[[
		Nejdůležitější test v souboru: pustí `init.server.luau`.

		Provede se tím veškerý kód, který v Robloxu běží při startu —
		stavba světa, napojení remotů, nastartování všech služeb. Chyba
		jako `Remotes.Neexistuje` se projeví přesně tady.
	]]
	t.test("server nastartuje", function()
		t.entry("server")()
	end)

	-- Struktura po startu ----------------------------------------------------

	t.test("remoty vznikly v ReplicatedStorage", function()
		local storage = t.stub().service("ReplicatedStorage")
		local folder = storage:FindFirstChild("Remotes")
		t.assert(folder ~= nil, "složka Remotes chybí")
	end)

	--[[
		Každý definovaný remote musí po startu existovat jako instance.
		Kdyby se název v definicích rozešel s tím, co kód používá,
		pozná se to tady, ne až u hráče.
	]]
	t.test("každý definovaný remote existuje", function()
		local Remotes = t.require("Remotes")
		local storage = t.stub().service("ReplicatedStorage")
		local folder = storage:FindFirstChild("Remotes")

		local names = {
			"Collect", "Smash", "SaveSettings", "PromptPass", "PromptProduct",
			"TradeRequest", "TradeRespond", "TradeOffer", "TradeConfirm", "TradeCancel",
			"BuyUpgrade", "BuyWorld", "BuyBoost", "BuySquishy", "HoldSquishy", "Squeeze",
			"ClaimDaily", "ClaimQuest", "RedeemCode", "DoRebirth", "GetProfile",
			"TradeCandidates", "ProfileChanged", "PowerChanged", "GiantWall",
			"EquipCosmetic", "BuyPerk", "ExchangeGems",
		}

		for _, name in names do
			t.assert(folder:FindFirstChild(name) ~= nil, `remote {name} nevznikl`)
			-- A hlavně: přístup přes modul nesmí spadnout na assertu
			t.assert(Remotes[name] ~= nil, `Remotes.{name} není dostupný`)
		end
	end)

	--[[
		Připojení hráče je druhý největší kus startovního kódu: načtení
		profilu ze zámku, offline odměna, questy, kosmetika, statistiky.
		Bez tohohle testu by se `onPlayerAdded` v CI nikdy nespustilo.
	]]
	t.test("hráč se připojí a dostane profil", function()
		local players = t.world().players
		local player = players:_add("Tester", 1234)

		local DataService = t.require("DataService")
		local profile = DataService.get(player)

		t.assert(profile ~= nil, "profil se nenačetl")
		t.equal(profile.WorldIndex, 1, "začíná se v prvním světě")
		t.equal(profile.Barrier, 1, "začíná se u první zdi")

		-- Kosmetika se replikuje atributem, ne remotem
		t.equal(player:GetAttribute("CosmeticTrail"), "none", "atribut stopy")
		t.equal(player:GetAttribute("CosmeticAura"), "none", "atribut aury")
		t.equal(player:GetAttribute("CosmeticSkin"), "none", "atribut skinu")
	end)

	--[[
		Nasazení kusu, na který hráč nemá, musí server odmítnout —
		odemčení se nikde neukládá, takže tohle je jediná zábrana.
	]]
	t.test("kosmetiku bez nároku server nedá", function()
		local players = t.world().players
		local player = players:_add("Cheater", 4321)

		local Cosmetic = t.require("CosmeticService")

		t.assert(not Cosmetic.equip(player, "trail", "prism"), "prism prošel bez rebirthů")
		t.assert(not Cosmetic.equip(player, "trail", "vymyslene"), "neexistující id prošlo")
		t.assert(not Cosmetic.equip(player, "hlava", "none"), "neznámý druh prošel")
		t.assert(not Cosmetic.equip(player, "skin", "gold"), "zlatý skin prošel bez rebirthů")
		t.assert(Cosmetic.equip(player, "trail", "none"), "'none' neprošlo")

		-- Po průrazech na to nárok je
		local profile = t.require("DataService").get(player)
		profile.Smashes = 25
		t.assert(Cosmetic.equip(player, "trail", "spark"), "spark neprošel s 25 průrazy")
		t.equal(player:GetAttribute("CosmeticTrail"), "spark", "atribut se nepřepsal")
	end)

	--[[
		Prolnuté díly jsou vada, kterou kompilace nevidí a ve Studiu se
		pozná jen tím, že si jí někdo všimne. Stalo se to: dekorativní
		tabule u startu si sedla na skutečný žebříček, který tam staví
		jiná služba.

		Nestačí porovnávat středy — dva díly se prolnou, i když středy
		mají jinde. Počítá se proto **objem průniku** jejich kvádrů.
		Hlásí se až od 60 %, protože lehké dotyky jsou po celé trati
		záměrné (svit uvnitř sloupu, lem na podlaze); teprve díl z větší
		části pohřbený v jiném je skoro vždycky chyba.

		Rotace se zanedbává, takže test spíš přestřelí než podstřelí —
		u kontroly, která má chytat hrubé chyby, je to správný směr.
	]]
	t.test("u startu se díly navzájem nepohřbívají", function()
		local Track = t.require("Track")
		local world = t.stub().service("Workspace")
		local origin = Track.origin(1)

		local boxes = {}

		local function collect(node)
			for _, child in node:GetChildren() do
				if child.ClassName == "Part" and child.Position and child.Size then
					local at = child.Position
					local near = math.abs(at.X - origin.X) < 70
						and at.Z > origin.Z - 70
						and at.Z < origin.Z + 20

					if near then
						table.insert(boxes, { Name = child.Name, At = at, Size = child.Size })
					end
				end
				collect(child)
			end
		end

		collect(world)

		local function overlap(a, b, axis: string): number
			local halfA = (a.Size :: any)[axis] / 2
			local halfB = (b.Size :: any)[axis] / 2
			local low = math.max((a.At :: any)[axis] - halfA, (b.At :: any)[axis] - halfB)
			local high = math.min((a.At :: any)[axis] + halfA, (b.At :: any)[axis] + halfB)
			return math.max(high - low, 0)
		end

		for i = 1, #boxes do
			for j = i + 1, #boxes do
				local a, b = boxes[i], boxes[j]
				local shared = overlap(a, b, "X") * overlap(a, b, "Y") * overlap(a, b, "Z")

				if shared > 0 then
					local volumeA = a.Size.X * a.Size.Y * a.Size.Z
					local volumeB = b.Size.X * b.Size.Y * b.Size.Z
					local smaller = math.min(volumeA, volumeB)

					t.assert(
						smaller <= 0 or shared / smaller < 0.6,
						`{a.Name} a {b.Name} se prolínají z `
							.. `{math.floor(shared / smaller * 100)} %`
					)
				end
			end
		end
	end)

	--[[
		Tabule u spawnu. V žánru je to první věc, na kterou hráč kouká,
		a její řádky se skládají z několika kusů — když jeden vypadne,
		tabule se nerozbije, jen tiše ztratí portréty nebo čísla.
	]]
	--[[
		Výzdoba, kterou není odkud vidět.

		Chodba je uzavřená krabice: neprůhledné stěny po stranách
		a žebra nad hlavou. Cokoliv postavené za stěnou a pod jejich
		výškou tedy fyzicky existuje a nejde spatřit — a přesně to se
		stalo obřím rekvizitám i plovoucím krám, protože obojí vzniklo
		dřív, než chodba dostala strop.

		Od chvíle, kdy je z chodby hala, je pravidlo jednodušší: co je
		uvnitř haly, je vidět. Neviditelné je jen to, co skončí za
		vzdálenou stěnou nebo nad stropem.
	]]
	t.test("žádná výzdoba není za stěnou haly", function()
		local Track = t.require("Track")
		local Config = t.require("Config")
		local TRACK = Config.Track
		local half = TRACK.HallWidth / 2
		local ceiling = TRACK.HallHeight - TRACK.DeckDrop

		local origin = Track.origin(1)
		local worlds = t.stub().service("Workspace"):FindFirstChild("Worlds")
		local folder = worlds:FindFirstChild(Config.Worlds[1].Id)

		local DECOR = { "Obří ", "Kra", "Výzdoba" }

		local function isDecor(name: string): boolean
			for _, prefix in DECOR do
				if string.sub(name, 1, #prefix) == prefix then
					return true
				end
			end
			return false
		end

		local hidden = 0
		local example = ""

		for _, child in folder:GetChildren() do
			if child.ClassName ~= "Part" or not child.Position or not isDecor(child.Name) then
				continue
			end

			local across = math.abs(child.Position.X - origin.X)
			local height = child.Position.Y

			if across >= half or height >= ceiling then
				hidden += 1
				example = child.Name
			end
		end

		t.equal(hidden, 0, `{hidden} kusů výzdoby leží mimo halu (třeba {example})`)
	end)

	--[[
		Rekvizity za zábradlím stojí na terase, ne ve vzduchu.

		Terasa je o šest studů níž než dráha. Kdo na ten rozdíl zapomene,
		nechá všechny rekvizity ve všech světech viset přesně o výšku
		terasy nad zemí — a ve Studiu to z dráhy vypadá jako záměr,
		dokud si člověk nestoupne vedle nich.
	]]
	--[[
		Mezi vyvýšenou dráhou a terasou nesmí zůstat štěrbina.

		Deska dráhy má tloušťku `DeckDrop`, takže její spodek přesně
		dosedne na povrch terasy. Když se jedno z těch čísel změní a
		druhé ne, vznikne pod dráhou mezera, kterou je z terasy vidět
		skrz — a spraví se to samo jen do chvíle, než někdo halu
		prohloubí.
	]]
	--[[
		Povrchová výzdoba se musí něčeho držet.

		Díry, posyp a bubliny mají ležet na podlaze nebo na stěně haly.
		Třikrát po sobě skončily ve vzduchu, protože se posunulo to, na
		čem visely, a ony zůstaly na starém místě. Test proto neměří,
		jestli jsou vidět, ale jestli se dotýkají nějakého povrchu —
		plovoucí kus je vidět taky, jen vypadá jako závada.

		Obří hračky a kry se schválně nekontrolují: ty se vznášet mají.
	]]
	--[[
		Dráhu nesmí jít opustit skokem.

		Zábradlí je nízké schválně, aby bylo vidět do haly — jenže
		postava v Robloxu doskočí výš, než je zábradlí vysoké. Bez
		zábrany nad ním se dá seskočit na terasu a **obejít každou zeď**,
		čímž se celý postup hrou dá přeskákat. Je to chyba, která se
		nikde neprojeví jako chyba: jen jako hráč s podezřele vysokým
		skóre.

		Test proto počítá souvislou překážku od podlahy nahoru a chce
		aspoň dvacet studů — víc, než kolik postava doskočí, i kdyby se
		odrazila z čehokoliv na dráze.
	]]
	--[[
		Obří zeď stojí vedle dráhy, ne v ní.

		Je to velký díl u spawnu a dvakrát se pohnul terén pod ním:
		nejdřív vzniklo zábradlí s neviditelnou zábranou, pak terasa
		o šest studů níž. Zeď tím půlkou trčela skrz překážku, do které
		hráč naráží, a druhou půlkou se vznášela.

		Test měří obojí naráz: vnitřní hrana musí být za zábranou a
		spodek musí sedět na terase.
	]]
	--[[
		Jmenovka nad hlavou.

		Je to jediné místo, kde hráč vidí postup ostatních za běhu —
		tabulka u spawnu je daleko a nikdo se k ní nevrací. Text je
		zároveň ta část, která se dá splést, takže se skládá zvlášť
		a dá se zkontrolovat bez postavy a billboardu.
	]]
	t.test("jmenovka ukazuje titul, jméno i průrazy", function()
		local PlayerService = t.require("PlayerService")
		local Format = t.require("Format")

		local title, lines = PlayerService.nameplate({
			Smashes = 12500,
			Rebirths = 0,
			Title = "Rookie",
		}, "Tester")

		t.assert(title ~= nil, "titul se nedohledal")
		t.equal(lines.Name, "Tester", "jméno na jmenovce nesedí")
		t.assert(
			string.find(lines.Stat, Format.short(12500), 1, true) ~= nil,
			`na jmenovce chybí počet průrazů: {lines.Stat}`
		)
		t.assert(string.find(lines.Title, "⭐") == nil, "bez rebirthu se ukazuje hvězdička")
	end)

	t.test("rebirthy se lepí k titulu, ne na vlastní řádek", function()
		local PlayerService = t.require("PlayerService")

		local _, lines = PlayerService.nameplate({
			Smashes = 40,
			Rebirths = 7,
			Title = "Rookie",
		}, "Tester")

		t.assert(string.find(lines.Title, "⭐7", 1, true) ~= nil, `chybí počet rebirthů: {lines.Title}`)
	end)

	--[[
		Portál do dalšího světa na konci trati.

		Světy se dřív kupovaly jen z menu, takže postup mezi nimi nebyl
		nikde vidět. Test hlídá dvě věci, na kterých to stojí: že portál
		je za posledním světem vynechaný (není kam) a že ho klient najde
		podle značky — bez ní by brána stála na trati a nešlo by do ní
		vejít.
	]]
	t.test("portál stojí u každého světa kromě posledního", function()
		local Config = t.require("Config")
		local worlds = t.stub().service("Workspace"):FindFirstChild("Worlds")

		local built = 0
		for index, world in Config.Worlds do
			local folder = worlds:FindFirstChild(world.Id)
			t.assert(folder ~= nil, `svět {world.Name} se nepostavil`)

			local found = false
			for _, child in folder:GetChildren() do
				if child.Name == "Brána světa" then
					found = true
					t.equal(
						child:GetAttribute("World"),
						Config.Worlds[index + 1] and Config.Worlds[index + 1].Id,
						`portál ve světě {world.Name} míří jinam`
					)
				end
			end

			if index < #Config.Worlds then
				t.assert(found, `svět {world.Name} nemá portál dál`)
				built += 1
			else
				t.assert(not found, "za posledním světem stojí portál, kam nevede")
			end
		end

		local tagged = t.stub().service("CollectionService"):GetTagged("WorldPortal")
		t.equal(#tagged, built, "některý portál nemá značku WorldPortal")
	end)

	t.test("obří zeď stojí na terase mimo dráhu", function()
		local Track = t.require("Track")
		local Config = t.require("Config")
		local TRACK = Config.Track

		local folder = t.stub().service("Workspace"):FindFirstChild("GiantWall")
		t.assert(folder ~= nil, "obří zeď se nepostavila")

		local wall = folder:FindFirstChild("Wall")
		t.assert(wall ~= nil, "chybí samotná deska zdi")

		local origin = Track.origin(1)
		local inner = math.abs(wall.Position.X - origin.X) - wall.Size.X / 2
		local bottom = wall.Position.Y - wall.Size.Y / 2

		t.assert(
			inner >= TRACK.Width / 2 + 2,
			`vnitřní hrana zdi je {math.floor(inner)} od osy, zábrana dráhy končí na {TRACK.Width / 2 + 2}`
		)
		t.assert(
			math.abs(bottom + TRACK.DeckDrop) < 1,
			`zeď začíná ve výšce {bottom}, terasa je na {-TRACK.DeckDrop}`
		)
	end)

	t.test("z dráhy se nedá vyskočit", function()
		local Track = t.require("Track")
		local Config = t.require("Config")
		local TRACK = Config.Track
		local NEEDED = 20

		local origin = Track.origin(1)
		local worlds = t.stub().service("Workspace"):FindFirstChild("Worlds")
		local folder = worlds:FindFirstChild(Config.Worlds[1].Id)

		for _, side in { -1, 1 } do
			local edge = origin.X + side * TRACK.Width / 2

			--[[
				Sesbírá se, kudy všude je na kraji dráhy pevno, a hledá
				se souvislý pás od země nahoru. Jedna vysoká zeď i dvě
				na sebe navazující jsou stejně dobré řešení, takže se
				měří výsledek, ne konkrétní díl.

				Počítají se ale jen díly, které jdou **po celé délce**.
				První verze tohohle testu na to zapomněla a procházela
				i s vypnutou zábranou: držely ji sloupy oblouků, které
				stojí jen na dvanácti místech. Mezi nimi se dalo
				vyskočit úplně stejně a test o tom mlčel.
			]]
			local full = Track.length() * 0.8

			local spans = {}
			for _, child in folder:GetChildren() do
				if child.ClassName ~= "Part" or not child.Position or not child.CanCollide then
					continue
				end
				if child.Size.Z < full then
					continue
				end

				local low = child.Position.X - child.Size.X / 2
				local high = child.Position.X + child.Size.X / 2
				if edge < low - 1 or edge > high + 1 then
					continue
				end

				table.insert(spans, {
					Bottom = child.Position.Y - child.Size.Y / 2,
					Top = child.Position.Y + child.Size.Y / 2,
				})
			end

			table.sort(spans, function(a, b)
				return a.Bottom < b.Bottom
			end)

			local reach = 0
			for _, span in spans do
				if span.Bottom <= reach + 0.5 then
					reach = math.max(reach, span.Top)
				end
			end

			t.assert(
				reach >= NEEDED,
				`na straně {side} končí pevná stěna ve výšce {reach}, potřeba je {NEEDED}`
			)
		end
	end)

	t.test("výzdoba povrchu se drží povrchu", function()
		local Track = t.require("Track")
		local Config = t.require("Config")
		local TRACK = Config.Track

		local origin = Track.origin(1)
		local worlds = t.stub().service("Workspace"):FindFirstChild("Worlds")
		local folder = worlds:FindFirstChild(Config.Worlds[1].Id)

		local floating = 0
		local example = ""

		for _, child in folder:GetChildren() do
			if child.ClassName ~= "Part" or not child.Position then
				continue
			end
			if string.sub(child.Name, 1, 9) ~= "Výzdoba " then
				continue
			end

			local across = math.abs(child.Position.X - origin.X)
			local bottom = child.Position.Y - child.Size.Y / 2

			local onHallWall = math.abs(across - TRACK.HallWidth / 2) < 3
			local onTrack = math.abs(bottom) < 2
			local onDeck = math.abs(bottom + TRACK.DeckDrop) < 2

			if not (onHallWall or onTrack or onDeck) then
				floating += 1
				example = `{child.Name} v {math.floor(across)}/{math.floor(bottom)}`
			end
		end

		t.equal(floating, 0, `{floating} kusů výzdoby se nedrží ničeho (třeba {example})`)
	end)

	t.test("dráha dosedá na terasu bez štěrbiny", function()
		local Config = t.require("Config")
		local TRACK = Config.Track

		local worlds = t.stub().service("Workspace"):FindFirstChild("Worlds")
		local folder = worlds:FindFirstChild(Config.Worlds[1].Id)

		local slab, deck
		for _, child in folder:GetChildren() do
			if child.ClassName ~= "Part" or not child.Position then
				continue
			end
			if string.sub(child.Name, 1, 8) == "Podlaha " then
				slab = slab or child
			elseif child.Name == "Terasa" then
				deck = deck or child
			end
		end

		t.assert(slab ~= nil, "deska dráhy chybí")
		t.assert(deck ~= nil, "terasa chybí")

		local slabBottom = slab.Position.Y - slab.Size.Y / 2
		local deckTop = deck.Position.Y + deck.Size.Y / 2

		t.assert(
			math.abs(slabBottom - deckTop) < 0.01,
			`dráha končí v {slabBottom}, terasa začíná v {deckTop} — mezera pod dráhou`
		)
	end)

	t.test("rekvizity za zábradlím stojí na terase", function()
		local Track = t.require("Track")
		local Config = t.require("Config")
		local TRACK = Config.Track

		local origin = Track.origin(1)
		local worlds = t.stub().service("Workspace"):FindFirstChild("Worlds")
		local folder = worlds:FindFirstChild(Config.Worlds[1].Id)
		local props = folder and folder:FindFirstChild("Rekvizity")

		t.assert(props ~= nil, "složka s rekvizitami chybí")

		local lowest = math.huge
		local checked = 0

		local function walk(node)
			for _, child in node:GetChildren() do
				if child.ClassName == "Part" and child.Position then
					local across = math.abs(child.Position.X - origin.X)
					if across > TRACK.Width / 2 then
						checked += 1
						local bottom = child.Position.Y - child.Size.Y / 2
						lowest = math.min(lowest, bottom)
					end
				end
				walk(child)
			end
		end

		walk(props)

		t.assert(checked > 0, "za zábradlím nestojí jediná rekvizita")
		t.assert(
			lowest <= -TRACK.DeckDrop + 2,
			`nejnižší rekvizita začíná ve výšce {lowest}, terasa je na {-TRACK.DeckDrop}`
		)
	end)

	t.test("tabule u spawnu má úplné řádky", function()
		local folder = t.stub().service("Workspace"):FindFirstChild("Leaderboard")
		t.assert(folder ~= nil, "tabule se vůbec nepostavila")

		local panel = folder:FindFirstChild("Tabule")
		t.assert(panel ~= nil, "chybí samotná deska")

		local board = panel:FindFirstChild("Board")
		t.assert(board ~= nil, "deska nemá SurfaceGui")

		local rows = 0
		local function walk(node)
			for _, child in node:GetChildren() do
				if string.sub(child.Name, 1, 3) == "Row" then
					rows += 1
					for _, part in { "Avatar", "Rank", "PlayerName", "Value" } do
						t.assert(
							child:FindFirstChild(part) ~= nil,
							`{child.Name}: chybí {part}`
						)
					end
				end
				walk(child)
			end
		end
		walk(board)

		t.assert(rows >= 10, `tabule má jen {rows} řádků`)
	end)

	t.test("svět se postavil", function()
		local world = t.stub().service("Workspace")
		t.assert(world:FindFirstChild("Worlds") ~= nil, "složka Worlds chybí")
	end)

	--[[
		Trať není jen podlaha a dvě zdi — má oblouky, sloupy, prahy
		a plovoucí kry. Kdyby se stavba některé vrstvy tiše rozbila,
		hra by pořád naběhla a vypadala by jako prototyp. Počítá se
		proto, co ve světě opravdu vzniklo.
	]]
	t.test("trať má postavenou architekturu, ne jen podlahu", function()
		local Config = t.require("Config")
		local worlds = t.stub().service("Workspace"):FindFirstChild("Worlds")
		local folder = worlds:FindFirstChild(Config.Worlds[1].Id)

		t.assert(folder ~= nil, "složka prvního světa chybí")

		local counts = {}
		for _, child in folder:GetChildren() do
			counts[child.Name] = (counts[child.Name] or 0) + 1
		end

		local barriers = Config.Track.BarrierCount

		--[[
			Podlaha je po úsecích, ne jedním kusem — každý úsek nese barvu
			a materiál své zóny. Počítají se proto všechny díly, jejichž
			jméno podlahou začíná.
		]]
		local floors = 0
		local zoneIds = {}
		for name, n in counts do
			if string.sub(name, 1, 8) == "Podlaha " then
				floors += n
				zoneIds[string.sub(name, 9)] = true
			end
		end

		t.assert(floors == barriers + 1, `podlahových úseků je {floors}, čekáno {barriers + 1}`)

		-- Zón musí být na trati vidět víc než jedna, jinak se terén nemění
		local distinct = 0
		for _ in zoneIds do
			distinct += 1
		end
		t.assert(distinct >= 3, `na trati je jen {distinct} druh(y) terénu — nemění se`)
		t.assert((counts["Sloup oblouku"] or 0) == barriers * 2, "oblouky nejsou u každé zdi")
		t.assert((counts["Překlad oblouku"] or 0) == barriers, "chybí překlady oblouků")
		t.assert((counts["Sloup"] or 0) == barriers * 2, "chybí sloupy mezi zdmi")
		t.assert((counts["Kra"] or 0) > 10, "chybí plovoucí pozadí")
		t.assert((counts["Práh"] or 0) > 20, "chybí prahy v podlaze")

		--[[
			Nákupní desky na trati. Bez nich je chodba prázdná a
			vylepšení se dají koupit jen z menu — což je přesně ten
			rozdíl mezi "hřiště" a "tunel".
		]]
		local pads = 0
		for name, n in counts do
			if string.sub(name, 1, 4) == "Pad " then
				pads += n
			end
		end
		t.assert(pads >= #Config.Upgrades, `desek je jen {pads}, vylepšení {#Config.Upgrades}`)

		--[[
			Klient je hledá podle značky, ne podle jména. Kdyby značka
			chyběla, desky by stály na trati a nešlo by na nich koupit
			vůbec nic.
		]]
		local tagged = 0
		for _, pad in t.stub().service("CollectionService"):GetTagged("BuyPad") do
			-- Značek je tolik, kolik má hra světů; počítá se jen ten první
			if pad.Parent == folder then
				tagged += 1
			end
		end
		t.equal(tagged, pads, "některá deska nemá značku BuyPad")

		--[[
			Desky leží na podlaze — nad dlaždicemi, ale na dosah kroku.

			Původní verze tohohle testu měřila jen "je nad dlaždicemi",
			a od chvíle, kdy si výšku desky i podlahy počítá `Config`
			ze stejného čísla, se stala tautologií: obě strany se
			posunou spolu a nikdy se nerozejdou.

			Cenu má proto až **odstup**. Ten je pořád napsaný ručně,
			takže se dá splést — a chybný odstup je buď deska zahrabaná
			v dlaždicích, nebo deska ve vzduchu, na kterou se nedá
			stoupnout.
		]]
		local floor = Config.floorTop()
		local pads = 0

		for _, child in folder:GetChildren() do
			if child.ClassName == "Part" and child.Position and string.sub(child.Name, 1, 4) == "Pad " then
				pads += 1
				local lift = child.Position.Y - child.Size.Y / 2 - floor

				t.assert(lift >= 0, `{child.Name} je zahrabaná v dlaždicích o {-lift}`)
				t.assert(lift <= 2, `{child.Name} se vznáší {lift} studů nad podlahou`)
			end
		end

		t.assert(pads > 0, "na trati není jediná deska")

		--[[
			Cedule levelu visí na OBOU stěnách. Jedna by stačila jen
			hráči, který kouká správným směrem — a to je ta polovina,
			která si pak stěžuje, že neví, kde je.
		]]
		local signs = 0
		for name, n in counts do
			if string.sub(name, 1, 7) == "Cedule " then
				signs += n
			end
		end
		t.equal(signs, barriers * 2, `cedulí je {signs}, čekáno {barriers * 2}`)

		--[[
			Cenovka pod obří hračkou. Bez ní je rekvizita jen dekorace
			a hráč nemá jak zjistit, že to, kolem čeho běží, se dá
			koupit — přesně ta informace, kvůli které vůbec stojí u trati.
		]]
		local plaques = 0
		for name, n in counts do
			if string.sub(name, 1, 8) == "Cenovka " then
				plaques += n
			end
		end
		t.equal(plaques, barriers, `cenovek je {plaques}, čekáno {barriers}`)

		-- Obří rekvizity: bez nich je trať zase jen barevná chodba
		local giants = 0
		for name, n in counts do
			if string.sub(name, 1, 7) == "Obří " then
				giants += n
			end
		end
		t.assert(giants > 10, `u trati stojí jen {giants} kusů obřích rekvizit`)

		--[[
			Strop dělá z chodby tunel. Bez něj je to příkop a rychlost
			nemá o co se opřít — proto se počítají žebra i to, že jich
			je nad trať dost, ne jen pár u startu.
		]]
		local ribs = 0
		for name, n in counts do
			if string.sub(name, 1, 7) == "Žebro " then
				ribs += n
			end
		end
		t.assert(ribs > 40, `žeber je jen {ribs} — chodba nemá strop`)
	end)

	-- Rozhraní mezi moduly -------------------------------------------------------

	--[[
		Volání mezi službami kompilace neověřuje. Statickou kontrolu dělá
		`tools/lint.py` nad sdílenými moduly; tenhle test hlídá služby,
		které se volají přes `require` uvnitř funkcí, kam lint nevidí.
	]]
	t.test("služby mají funkce, které po sobě volají", function()
		local expectations = {
			MilestoneService = { "rebirth", "world", "squishy" },
			DataService = { "load", "get", "await", "save", "release", "markDirty", "playtime" },
			GameService = { "pushProfile", "serialize", "teleport", "applyCharacter", "enterWorld" },
			SquishyService = { "slots", "snapshot", "multiplier", "grant", "buy", "hold", "squeeze" },
			RetentionService = { "progress", "reach", "push", "ensureQuests", "snapshot" },
			EventService = { "contribute", "snapshot" },
			MonetizationService = { "refreshPasses", "pushOffers", "checkBadges", "offers" },
			PlayerService = { "setupStats", "grantOffline", "refreshNameplate", "applyCollisionGroup" },
			WorldService = { "build" },
			TradeService = { "request", "respond", "offer", "confirm", "cancel", "candidates" },
			AnalyticsService = { "onboarding", "economy", "world", "custom", "markNew" },
			GuardService = { "allow", "wrapFunction", "wrapEvent" },
			CosmeticService = { "apply", "equip" },
			ShopService = { "buyUpgrade", "buyWorld", "buyBoost", "equipTitle", "claimChest", "rebirth", "buyPerk", "exchange" },
		}

		for moduleName, functions in expectations do
			local module = t.require(moduleName)
			for _, functionName in functions do
				t.assert(
					typeof(module[functionName]) == "function",
					`{moduleName}.{functionName} chybí nebo není funkce`
				)
			end
		end
	end)

	--[[
		Ekonomika se počítá i na klientovi (kvůli UI), takže musí umět
		pracovat s obyčejnou tabulkou, ne jen s živým profilem.
	]]
	t.test("ekonomika spočítá hodnoty nad prostým profilem", function()
		local Economy = t.require("Economy")
		local Config = t.require("Config")

		local Live = t.require("Live")

		local profile = {
			Coins = 0, Gems = 0, Power = 0, WorldIndex = 1, Barrier = 1,
			Worlds = { [Config.Worlds[1].Id] = true },
			Upgrades = {}, Boosts = {}, Rebirths = 0, Smashes = 0,
			Squishies = {}, Held = {}, Passes = {},
		}

		t.assert(Economy.pickupValue(profile, 0) >= 1, "hodnota pickupu")
		t.assert(Economy.walkSpeed(profile) > 0, "rychlost běhu")
		t.assert(Economy.collectRadius(profile) > 0, "dosah sbírání")
		t.assert(Economy.squishMultiplier(profile) == 1, "bez hraček v ruce žádný bonus")
		--[[
			Čas mimo okno dvojnásobku. V nule totiž okno pro celý server
			zrovna běží a násobič je dvojka — test by tvrdil, že
			ekonomika je rozbitá, i když funguje přesně jak má.
		]]
		local quiet = Live.Happy.LengthSeconds + 60
		t.assert(Economy.coinMultiplier(profile, quiet) == 1, "bez rebirthu žádný bonus")
		t.assert(Economy.coinsPerSecond(profile, 0) > 0, "příjem")
	end)

	--[[
		Trať musí sedět sama se sebou: index pickupu se musí dát rozložit
		zpátky na segment. Kdyby se to rozešlo, server by odmítal sbírání,
		které klient považuje za platné.
	]]
	t.test("geometrie tratě je konzistentní", function()
		local Track = t.require("Track")
		local Config = t.require("Config")

		t.equal(
			Track.PickupCount,
			Track.PickupsPerSegment * Config.Track.BarrierCount,
			"počet pickupů"
		)

		for segment = 1, Config.Track.BarrierCount do
			for _, index in Track.segmentPickups(segment) do
				t.equal(Track.pickupSegment(index), segment, `pickup {index} patří do segmentu`)
			end
		end
	end)

	t.test("každý svět má dosažitelnou první zeď", function()
		local Config = t.require("Config")

		for index, world in Config.Worlds do
			local needed = Config.barrierPower(index, 1)
			t.assert(needed > 0, `{world.Name}: první zeď`)
			-- Musí jít prorazit rozumným počtem pickupů daného světa
			t.assert(needed / world.Pickup < 100, `{world.Name}: první zeď je moc drahá`)
		end
	end)
end

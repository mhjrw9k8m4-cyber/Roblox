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
		PetService = "start",
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
			"BuyUpgrade", "BuyWorld", "BuyBoost", "BuyEgg", "EquipPet", "MergePet",
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
	end)

	-- Rozhraní mezi moduly -------------------------------------------------------

	--[[
		Volání mezi službami kompilace neověřuje. Statickou kontrolu dělá
		`tools/lint.py` nad sdílenými moduly; tenhle test hlídá služby,
		které se volají přes `require` uvnitř funkcí, kam lint nevidí.
	]]
	t.test("služby mají funkce, které po sobě volají", function()
		local expectations = {
			DataService = { "load", "get", "await", "save", "release", "markDirty", "playtime" },
			GameService = { "pushProfile", "serialize", "teleport", "applyCharacter", "enterWorld" },
			PetService = { "slots", "snapshot", "multiplier", "grantFromEgg", "buyEgg", "merge" },
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

		local profile = {
			Coins = 0, Gems = 0, Power = 0, WorldIndex = 1, Barrier = 1,
			Worlds = { [Config.Worlds[1].Id] = true },
			Upgrades = {}, Boosts = {}, Rebirths = 0, Smashes = 0,
			Pets = {}, EquippedPets = {}, Passes = {},
		}

		t.assert(Economy.pickupValue(profile, 0) >= 1, "hodnota pickupu")
		t.assert(Economy.walkSpeed(profile) > 0, "rychlost běhu")
		t.assert(Economy.collectRadius(profile) > 0, "dosah sbírání")
		t.assert(Economy.petMultiplier(profile) == 1, "bez petů žádný bonus")
		t.assert(Economy.coinMultiplier(profile, 0) == 1, "bez rebirthu žádný bonus")
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

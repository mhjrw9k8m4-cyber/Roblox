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
		"Build", "Track", "Lock", "Trade", "Throttle", "Assets",
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
		}

		for _, name in names do
			t.assert(folder:FindFirstChild(name) ~= nil, `remote {name} nevznikl`)
			-- A hlavně: přístup přes modul nesmí spadnout na assertu
			t.assert(Remotes[name] ~= nil, `Remotes.{name} není dostupný`)
		end
	end)

	t.test("svět se postavil", function()
		local world = t.stub().service("Workspace")
		t.assert(world:FindFirstChild("Worlds") ~= nil, "složka Worlds chybí")
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
			RetentionService = { "progress", "push", "ensureQuests", "snapshot" },
			EventService = { "contribute", "snapshot" },
			MonetizationService = { "refreshPasses", "pushOffers", "checkBadges", "offers" },
			PlayerService = { "setupStats", "grantOffline", "refreshNameplate", "applyCollisionGroup" },
			WorldService = { "build" },
			TradeService = { "request", "respond", "offer", "confirm", "cancel", "candidates" },
			AnalyticsService = { "onboarding", "economy", "world", "custom", "markNew" },
			GuardService = { "allow", "wrapFunction", "wrapEvent" },
			ShopService = { "buyUpgrade", "buyWorld", "buyBoost", "equipTitle", "claimChest", "rebirth" },
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

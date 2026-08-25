--!strict
--[[
	Hraní s kamarády.

	Roblox od konce roku 2025 neřadí hry podle počtu hráčů online, ale
	podle toho, jestli se hráč vrátí — a jedním z měřených signálů je
	společné hraní. Hra, do které si lidé zvou kamarády, dostane víc míst
	v doporučování než hra se stejným počtem lidí, kteří sedí každý sám.

	Testují se dvě věci, u kterých se chyba pozná až na číslech: že bonus
	opravdu roste s počtem kamarádů (a má strop) a že odměna za pozvání
	přijde jednou za člověka, ne pokaždé, co se ten člověk vrátí.
]]

return function(t)
	local Live = t.require("Live")
	local Economy = t.require("Economy")

	local function profile(fields)
		local base = {
			Coins = 0,
			Gems = 0,
			Power = 0,
			WorldIndex = 1,
			Barrier = 1,
			Rebirths = 0,
			Upgrades = {},
			Boosts = {},
			Perks = {},
			Passes = {},
			Laps = {},
			Held = {},
			Squishies = {},
			Referred = {},
		}
		for key, value in fields or {} do
			base[key] = value
		end
		return base
	end

	t.test("bonus roste s počtem kamarádů a má strop", function()
		t.equal(Economy.friendMultiplier(profile()), 1, "hráč bez kamarádů dostává bonus")

		local one = Economy.friendMultiplier(profile({ Friends = 1 }))
		t.assert(one > 1, "jeden kamarád nic nepřidal")

		local two = Economy.friendMultiplier(profile({ Friends = 2 }))
		t.assert(two > one, "druhý kamarád nic nepřidal")

		--[[
			Strop je tam, aby ze skupiny šesti lidí nebyl jiný řád
			ekonomiky než ze hry pro jednoho.
		]]
		local capped = Economy.friendMultiplier(profile({ Friends = Live.Social.MaxFriends }))
		local beyond = Economy.friendMultiplier(profile({ Friends = Live.Social.MaxFriends + 20 }))
		t.equal(beyond, capped, "nad stropem se bonus pořád zvětšuje")
	end)

	--[[
		Bonus musí být vidět na mincích, ne jen v tabulce. Kdyby se
		`coinMultiplier` o něj neopřel, byl by odznak v HUD slib, za
		kterým nic není.
	]]
	t.test("kamarádi se propíšou do mincí", function()
		local QUIET = 3600 * 5 + 600
		local alone = Economy.coinMultiplier(profile(), QUIET)
		local together = Economy.coinMultiplier(profile({ Friends = 2 }), QUIET)

		t.assert(together > alone, "s kamarády nepřibývá víc mincí")
		t.equal(
			together,
			alone * Economy.friendMultiplier(profile({ Friends = 2 })),
			"bonus se do mincí propisuje jinak, než jak ho ukazuje HUD"
		)
	end)

	t.test("odměna za pozvání přijde jednou za člověka", function()
		local DataService = t.require("DataService")
		local PartyService = t.require("PartyService")
		local players = t.world().players

		local host = players:_add("Hostitel", 60001)
		local guest = players:_add("Pozvany", 60002)

		local hostProfile = DataService.get(host)
		t.assert(hostProfile ~= nil, "profil hostitele se nenačetl")
		hostProfile.Gems = 0
		hostProfile.Referred = {}

		guest._joinData = { referredByPlayerId = host.UserId }

		PartyService.rewardReferral(guest)
		t.equal(hostProfile.Gems, Live.Social.ReferralGems, "za pozvání nepřišly gemy")

		--[[
			Ten samý člověk podruhé. Bez tohohle by stačilo, aby kamarád
			odešel a přišel znovu — a gemy by tekly donekonečna.
		]]
		PartyService.rewardReferral(guest)
		t.equal(hostProfile.Gems, Live.Social.ReferralGems, "za stejného člověka přišly gemy dvakrát")
	end)

	t.test("kdo přišel sám, nikomu nic nevydělá", function()
		local DataService = t.require("DataService")
		local PartyService = t.require("PartyService")
		local players = t.world().players

		local host = players:_add("Hostitel2", 60003)
		local alone = players:_add("Samotar", 60004)

		local hostProfile = DataService.get(host)
		hostProfile.Gems = 0
		hostProfile.Referred = {}

		-- Bez pozvánky: `referredByPlayerId` Roblox nevyplní
		PartyService.rewardReferral(alone)
		t.equal(hostProfile.Gems, 0, "gemy přišly i za hráče, kterého nikdo nepozval")
	end)

	--[[
		Počítá se jen ten, kdo je opravdu kamarád. Kdyby se počítal
		každý na serveru, dostal by bonus i ten, kdo nikoho nepozval —
		a signál "společné hraní", kvůli kterému to celé je, by se
		z toho vytratil.
	]]
	t.test("počítají se kamarádi, ne všichni na serveru", function()
		local PartyService = t.require("PartyService")
		local players = t.world().players

		local me = players:_add("Ja", 60005)
		local friend = players:_add("Kamarad", 60006)
		local stranger = players:_add("Cizi", 60007)

		me._friends[friend.UserId] = true
		friend._friends[me.UserId] = true

		t.equal(PartyService.countFriends(me), 1, "počet kamarádů nesedí")
		t.equal(PartyService.countFriends(stranger), 0, "cizí hráč má kamarády")
	end)
	--[[
		Společný průraz.

		Doporučení pro rok 2026 je mít ve hře aspoň jednu věc, která je
		s druhým člověkem opravdu LEPŠÍ, ne jen možná. Bonus za
		přítomnost kamaráda je pasivní — tenhle si musí oba odběhnout
		vedle sebe, a proto je okno krátké: delší by z toho udělalo
		"kdokoliv na serveru občas".
	]]
	t.test("dva u stejné zdi se potkají, sám u ní nikdo ne", function()
		local PartyService = t.require("PartyService")
		local players = t.world().players

		local first = players:_add("Prvni", 61001)
		local second = players:_add("Druhy", 61002)

		-- Sám: není s kým se potkat
		t.equal(PartyService.markSmash(first, 1, 3), nil, "první průraz našel partnera z ničeho")

		-- Ten samý hráč podruhé taky ne, jinak by stačilo běhat dokola
		t.equal(PartyService.markSmash(first, 1, 3), nil, "hráč se potkal sám se sebou")

		-- Druhý hráč hned po něm: potkali se
		t.equal(
			PartyService.markSmash(second, 1, 3),
			first,
			"dva u stejné zdi se nepotkali"
		)
	end)

	--[[
		Jiná zeď se nepočítá. Kdyby se počítala, stačilo by, aby si dva
		lidé hráli každý v jiné části trati — a "běželi jsme spolu" by
		neznamenalo nic.
	]]
	t.test("potkat se jde jen u té samé zdi", function()
		local PartyService = t.require("PartyService")
		local players = t.world().players

		local a = players:_add("Aa", 61003)
		local b = players:_add("Bb", 61004)

		PartyService.markSmash(a, 1, 7)
		t.equal(PartyService.markSmash(b, 1, 8), nil, "potkali se u různých zdí")
		t.equal(PartyService.markSmash(b, 2, 7), nil, "potkali se v různých světech")
	end)

	t.test("bonus za společný průraz dostanou oba", function()
		local DataService = t.require("DataService")
		local PartyService = t.require("PartyService")
		local players = t.world().players

		local a = players:_add("Spolu1", 61005)
		local b = players:_add("Spolu2", 61006)

		local profileA = DataService.get(a)
		local profileB = DataService.get(b)
		profileA.Coins = 0
		profileB.Coins = 0

		PartyService.rewardTogether(a, b, 1000)

		local expected = math.floor(1000 * Live.Social.TogetherBonus)
		t.equal(profileA.Coins, expected, "prvnímu nepřišel bonus")
		t.equal(profileB.Coins, expected, "druhému nepřišel bonus — bonus zná jen jeden")
	end)

end

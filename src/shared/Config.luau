--!strict
--[[
	Config — všechna čísla a texty hry na jednom místě.

	Hra: Power Smash. Hráč běží chodbou, sbírá "+1 Power", a když má dost,
	prorazí bariéru — ta se s ASMR zvukem rozsype na kusy. Za průrazy jsou
	peníze, za peníze vylepšení, za vylepšení rychlejší růst Poweru.

	Klíčové pravidlo ekonomiky:
	  Power je progres v rámci JEDNOHO světa. Nekupuje se za něj nic,
	  jen odemyká bariéry, a při přechodu do dalšího světa (nebo při
	  rebirthu) se vynuluje. Trvalý postup drží peníze, vylepšení a rebirthy.

	Zvuky a textury tady nejsou — mají vlastní modul `Assets`, protože
	se neřeší jedním ID, ale receptem z několika vrstev.
]]

local Config = {}

Config.GameName = "Power Smash"

-- Trať --------------------------------------------------------------------
Config.Track = {
	BarrierCount = 12, -- kolik bariér má jeden svět
	SegmentLength = 80, -- rozestup bariér (study)
	Width = 44, -- šířka běžecké dráhy
	--[[
		Hala kolem dráhy.

		Trať byla dlouho uzavřená chodba: dvaačtyřicet studů široká,
		šestadvacet vysoké neprůhledné stěny, strop nad hlavou. Vypadalo
		to jako roura a měla to jeden konkrétní následek — všechno, co
		se postavilo vedle dráhy, bylo za stěnou a nešlo to spatřit.
		Stalo se to třikrát po sobě.

		Velké hry v žánru běží v **hale**: dráha je uprostřed velké
		místnosti, po stranách je vidět daleko, u vzdálených stěn stojí
		velké rekvizity a nad tím vším je vysoký strop. Odtud ten dojem
		prostoru, který se barvami nedá nahradit.

		  `WallHeight` — jen zábradlí u dráhy, aby bylo vidět ven
		  `HallWidth`  — celá šířka místnosti (dráha je uprostřed)
		  `HallHeight` — kde je strop haly
		  `DeckDrop`   — o kolik je podlaha haly níž než dráha
	]]
	--[[
		Výška podlahy dráhy.

		Dlaždice staví klient a sedí na tmavším soklu; dohromady dávají
		povrch, po kterém se chodí. Číslo je tady, a ne u dlaždic,
		protože se podle něj musí řídit **všechno, co má na podlaze
		ležet** — nákupní desky, tekoucí pruhy, prahy. Když bylo jen
		v klientovi, zůstalo pod ním pokaždé něco zahrabaného: naposledy
		tekoucí pruhy ve výšce tří desetin studu.
	]]
	BaseHeight = 1.1,
	TileHeight = 1.7,

	WallHeight = 7,
	HallWidth = 184,
	HallHeight = 72,
	DeckDrop = 6,
	Lanes = { -13, 0, 13 }, -- pozice sloupců s pickupy
	RowOffsets = { 20, 36, 52, 68 }, -- kde v segmentu řady leží
	WorldSpacing = 500, -- rozestup světů, aby se nepřekrývaly
	--[[
		Růst požadavku a výplaty za každé dojeté kolo světa.

		Strop tam není kvůli hráči, ale kvůli stabilitě: dokud bariéru
		brzdí sbírání, je příjem za sekundu úměrný (Coins/Power)^kolo a
		drží se. Jakmile ale bariéra padne dřív, než k ní hráč doběhne,
		čas na kolo se zastaví na době běhu, výplata roste dál a příjem
		exploduje. Zastropované kolo tuhle smyčku ohraničí — po `LapCap`
		už farmení stejného světa nic nepřidá a je potřeba jít dál.
	]]
	LapPower = 1.9,
	LapCoins = 1.9,
	LapCap = 6,

	--[[
		Přeplácnutí (overkill): kolikrát víc Poweru hráč u zdi měl, než
		kolik potřeboval, se propíše do výplaty.

		Bez toho měly Power, štěstí, pety, rebirth i combo dohromady jeden
		jediný účinek — sundat zeď dřív. Jenže zdi stejně padají v okamžiku,
		kdy k nim doběhneš, takže všechny tyhle systémy končily v prázdnu
		a jedinou skutečnou statistikou byla rychlost běhu.

		Odmocnina, ne přímá úměra: přeplácnutí se má vyplatit, ale nesmí
		se stát hlavním zdrojem příjmu. Stokrát víc Poweru dá desetkrát
		víc peněz, ne stokrát.

		STROP JE POJISTKA, NE LADICÍ ČÍSLO. První verze ho měla na 100,
		jenže skutečný poměr je průměrně kolem 600 a špičkově desetitisíce
		— strop se tedy uplatnil skoro pokaždé a z přeplácnutí se stala
		konstanta. Tím se tiše vrátila přesně ta vada, kvůli které
		přeplácnutí vzniklo: Power, štěstí, pety a rebirth zase neměly
		kam ústit.

		Musí proto zůstat tak vysoko, aby se běžně neuplatnil. Hlídá to
		`simulate.py --max-clamped`.
	]]
	OverkillCap = 50000,
	OverkillCurve = 0.5,

	--[[
		Surge (nálet) — odměna za silný průraz.

		Do teď nebyl mezi průrazem a sbíráním žádný vztah: zeď spadla,
		hráč běžel dál a řetěz mu mezitím většinou stihl spadnout taky.
		Silný průraz teď na pár vteřin zrychlí běh a zvětší dosah, takže
		se hráč k dalším pickupům dostane dřív — a řetěz udrží.

		Vzniká tím smyčka, která dosud chyběla:
		    sbírej řetěz → velké přeplácnutí → nálet → udržíš řetěz

		Váže se na COMBO, ne na přeplácnutí. Přeplácnutí je skoro vždycky
		vysoké (hráč ke zdi dobíhá s přebytkem, ať dělá co dělá), takže
		by nálet běžel pořád a přestal by být odměnou. Řetěz naproti tomu
		hráč buď drží, nebo ne — to je skutečná dovednost.

		Práh 40 článků je zhruba půlka stropu: dá se udržet, ale ne
		omylem.
	]]
	SurgeAt = 40,
	SurgeSeconds = 4,
	SurgeSpeed = 1.35,
	SurgeRadius = 1.6,
	--[[
		Zlaté pickupy: kolik z tisíce jich je zlatých a kolikrát víc platí.

		Vzácnost je záměrně nízko. Kdyby zlatý pickup byl každý dvacátý,
		přestal by být nálezem a stal by se pozadím; takhle je to za celou
		trať pár kusů a hráč si každého všimne.
	]]
	GoldenPerMille = 22,
	GoldenValue = 25,
	PickupRespawn = 2.5, -- za jak dlouho se sebraný pickup vrátí
	CollectRadius = 7, -- základní dosah sbírání (magnet ho zvětšuje)
	SmashRadius = 9, -- jak blízko musí hráč být k bariéře
}

-- Světy -------------------------------------------------------------------
-- `Pickup` je základní hodnota jednoho "+1" v daném světě. Bariéry se od něj
-- odvozují, takže každý svět se hraje stejně a liší se jen měřítkem čísel —
-- tempo hry pak neurčuje svět, ale vylepšení a rebirthy.
--
-- `Price` dopočítal autoladič binárním hledáním nad simulací
-- (tools/simulate.py) na cílové časy odemčení: 12 min / 48 min / 2,2 h /
-- 5,2 h / 12,3 h aktivního hraní. Nejsou to odhady — a ručně by je
-- odhadnout ani nešlo, protože příjem závisí na combu, kolech světa
-- i přeplácnutí naráz. Po každé změně čísel to přepočítej.
Config.Worlds = {
	{
		Id = "Glass",
		Name = "Glass Hall",
		Price = 0,
		Pickup = 1,
		BarrierBase = 8,
		BarrierGrowth = 1.42,
		CoinBase = 14,
		CoinGrowth = 1.62,
		-- gemy padají jen za dokončené kolo, ne za jednotlivou bariéru
		Gems = 1,
		Color = Color3.fromRGB(150, 226, 255),
		Accent = Color3.fromRGB(86, 180, 255),
		Material = Enum.Material.Glass,
		Fog = Color3.fromRGB(28, 44, 68),
	},
	{
		Id = "Jelly",
		Name = "Jelly Cave",
		Price = 13456774,
		Pickup = 14,
		BarrierBase = 8,
		BarrierGrowth = 1.42,
		CoinBase = 210,
		CoinGrowth = 1.62,
		Gems = 2,
		Color = Color3.fromRGB(255, 106, 178),
		Accent = Color3.fromRGB(255, 60, 140),
		Material = Enum.Material.Glass,
		Fog = Color3.fromRGB(56, 22, 46),
	},
	{
		Id = "Ice",
		Name = "Ice Vault",
		Price = 3749719918,
		Pickup = 190,
		BarrierBase = 8,
		BarrierGrowth = 1.42,
		CoinBase = 3100,
		CoinGrowth = 1.62,
		Gems = 3,
		Color = Color3.fromRGB(198, 244, 255),
		Accent = Color3.fromRGB(120, 214, 255),
		Material = Enum.Material.Ice,
		Fog = Color3.fromRGB(26, 48, 62),
	},
	{
		Id = "Chocolate",
		Name = "Chocolate Factory",
		Price = 687130218586,
		Pickup = 2600,
		BarrierBase = 8,
		BarrierGrowth = 1.42,
		CoinBase = 46000,
		CoinGrowth = 1.62,
		Gems = 4,
		Color = Color3.fromRGB(124, 74, 44),
		Accent = Color3.fromRGB(198, 128, 72),
		Material = Enum.Material.Slate,
		Fog = Color3.fromRGB(42, 26, 18),
	},
	{
		Id = "Neon",
		Name = "Neon Core",
		Price = 23777678190053,
		Pickup = 36000,
		BarrierBase = 8,
		BarrierGrowth = 1.42,
		CoinBase = 680000,
		CoinGrowth = 1.62,
		Gems = 5,
		Color = Color3.fromRGB(255, 105, 220),
		Accent = Color3.fromRGB(150, 120, 255),
		Material = Enum.Material.Neon,
		Fog = Color3.fromRGB(34, 16, 54),
	},
	{
		Id = "Void",
		Name = "Void Prism",
		Price = 837810505970202,
		Pickup = 500000,
		BarrierBase = 8,
		BarrierGrowth = 1.42,
		CoinBase = 9800000,
		CoinGrowth = 1.62,
		Gems = 6,
		Color = Color3.fromRGB(176, 150, 255),
		Accent = Color3.fromRGB(96, 72, 200),
		Material = Enum.Material.Neon,
		Fog = Color3.fromRGB(14, 10, 28),
	},
	--[[
		Světy za Voidem.

		Šest světů odemkne odhodlaný hráč za jediný den — pak už ho drží
		jen kola a rebirthy, tedy ta samá trať pořád dokola. Tyhle čtyři
		jsou to, kam se dá jít dál: každý má vlastní paletu, materiál,
		zvuk průrazu, hudbu i rekvizity, takže se pozná i se zavřenýma
		očima.

		Čísla pokračují ve stejném poměru jako předchozí šestice
		(pickup a mince ×13,8 na svět, cena ×35). Přeskočit řadu by
		znamenalo, že se hráč do nového světa dostane dřív, než na něj
		bude mít vylepšení — a první zeď by ho zastavila na hodinu.
	]]
	{
		Id = "Nebula",
		Name = "Nebula Drift",
		Price = 29000000000000000,
		Pickup = 6900000,
		BarrierBase = 8,
		BarrierGrowth = 1.42,
		CoinBase = 135000000,
		CoinGrowth = 1.62,
		Gems = 7,
		Color = Color3.fromRGB(186, 130, 255),
		Accent = Color3.fromRGB(255, 120, 220),
		Material = Enum.Material.Neon,
		Fog = Color3.fromRGB(24, 14, 52),
	},
	{
		Id = "Solar",
		Name = "Solar Forge",
		Price = 1015000000000000000,
		Pickup = 95000000,
		BarrierBase = 8,
		BarrierGrowth = 1.42,
		CoinBase = 1900000000,
		CoinGrowth = 1.62,
		Gems = 8,
		Color = Color3.fromRGB(255, 158, 62),
		Accent = Color3.fromRGB(255, 96, 40),
		Material = Enum.Material.CrackedLava,
		Fog = Color3.fromRGB(58, 22, 8),
	},
	{
		Id = "Quantum",
		Name = "Quantum Bloom",
		Price = 35500000000000000000,
		Pickup = 1300000000,
		BarrierBase = 8,
		BarrierGrowth = 1.42,
		CoinBase = 26000000000,
		CoinGrowth = 1.62,
		Gems = 9,
		Color = Color3.fromRGB(140, 255, 226),
		Accent = Color3.fromRGB(60, 226, 255),
		Material = Enum.Material.Foil,
		Fog = Color3.fromRGB(10, 44, 44),
	},
	--[[
		Poslední svět. Za jeho dokončení se uděluje Void Core, jediná
		hračka, kterou nejde koupit ani vydřít z denního kolotoče —
		musí být na konci něco, co si hráč nemůže objednat.
	]]
	{
		Id = "Infinity",
		Name = "Infinity Garden",
		Price = 1240000000000000000000,
		Pickup = 18000000000,
		BarrierBase = 8,
		BarrierGrowth = 1.42,
		CoinBase = 360000000000,
		CoinGrowth = 1.62,
		Gems = 10,
		Color = Color3.fromRGB(255, 246, 214),
		Accent = Color3.fromRGB(255, 210, 96),
		Material = Enum.Material.Marble,
		Fog = Color3.fromRGB(46, 40, 30),
	},
}

--[[
	Vylepšení (nekonečný grind za peníze).

	Cena úrovně n = BasePrice * Growth^(n-1).

	`Scale` a `Suffix` slouží k tomu, aby šlo napsat, co hráč MÁ TEĎ
	a co bude mít po koupi. Bez toho nesla řádka jen statický popis
	("+2 studs of pickup reach") a otázku "vyplatí se mi to?" hráč
	zodpovědět nemohl — číslo, které si kupuje, nikde nebylo vidět.

	Účinek se odvozuje z `PerLevel`, ne opisuje: kdyby se čísla psala
	zvlášť, rozešla by se s tím, co vylepšení doopravdy dělá, při první
	úpravě rovnováhy.
]]
Config.Upgrades = {
	{
		Id = "Power",
		Name = "Power",
		Desc = "+50% to the value of every +1",
		Icon = "💪",
		MaxLevel = 60,
		BasePrice = 60,
		Growth = 1.32,
		PerLevel = 0.5,
		Scale = 100,
		Suffix = "%",
	},
	{
		Id = "Magnet",
		Name = "Magnet",
		Desc = "+2 studs of pickup reach",
		Icon = "🧲",
		MaxLevel = 25,
		BasePrice = 250,
		Growth = 1.45,
		PerLevel = 2,
		Scale = 1,
		Suffix = " studs",
	},
	{
		Id = "Speed",
		Name = "Speed",
		Desc = "+2 run speed",
		Icon = "⚡",
		MaxLevel = 25,
		BasePrice = 400,
		Growth = 1.5,
		PerLevel = 2,
		Scale = 1,
		Suffix = " speed",
	},
	{
		Id = "Luck",
		Name = "Luck",
		Desc = "+3% chance of a x5 pickup",
		Icon = "🍀",
		MaxLevel = 20,
		BasePrice = 1200,
		Growth = 1.55,
		PerLevel = 0.03,
		Scale = 100,
		Suffix = "%",
	},
	{
		Id = "Auto",
		Name = "Auto Collect",
		Desc = "+1 pickup collected for you every second",
		Icon = "🤖",
		MaxLevel = 12,
		BasePrice = 9000,
		Growth = 2.1,
		PerLevel = 1,
		Scale = 1,
		Suffix = "/s",
	},
	--[[
		Mačkání hračky je to, po čem se hra jmenuje, a do teď se dalo
		zlepšit jedině koupí dražší hračky nebo pasem. Vylepšení z něj
		dělá plnohodnotnou větev: hráč, kterému sedí mačkat, do ní může
		sypat mince místo do magnetu.
	]]
	{
		Id = "Squeeze",
		Name = "Grip Strength",
		Desc = "+15% power from every squeeze",
		Icon = "🤏",
		MaxLevel = 40,
		BasePrice = 900,
		Growth = 1.36,
		PerLevel = 0.15,
		Scale = 100,
		Suffix = "%",
	},
	--[[
		Řetěz drží jen pár vteřin a hráč ho ztratí pokaždé, když se
		zastaví u desky nebo obejde zeď. Prodloužení okna bylo do teď
		jen perk za rebirth — tedy něco, k čemu se nováček nedostane,
		přestože combo je mechanika, kterou musí pochopit hned.

		Strop je nízký schválně: okno delší než pár vteřin by z řetězu
		udělalo trvalý stav a násobič by přestal být za něco.
	]]
	{
		Id = "Chain",
		Name = "Chain Hold",
		Desc = "+0.1s before your chain drops",
		Icon = "🔗",
		MaxLevel = 20,
		BasePrice = 2400,
		Growth = 1.5,
		PerLevel = 0.1,
		Scale = 1,
		Suffix = "s",
	},
}

-- Boosty za gemy (časově omezené) -----------------------------------------
Config.Boosts = {
	{ Id = "Power2", Name = "×2 Power", Icon = "⚡", Gems = 19, Duration = 120, Field = "Power", Value = 2 },
	{ Id = "Coins2", Name = "×2 Coins", Icon = "💰", Gems = 15, Duration = 120, Field = "Coins", Value = 2 },
	{ Id = "Auto", Name = "Auto Collect", Icon = "🤖", Gems = 25, Duration = 180, Field = "Auto", Value = 6 },
}

-- Tituly nad hlavou (odemykají se za celkový počet průrazů) ----------------
Config.Titles = {
	{ Id = "Rookie", Name = "ROOKIE", Smashes = 0, Color = Color3.fromRGB(190, 196, 214) },
	{ Id = "Smasher", Name = "SMASHER", Smashes = 50, Color = Color3.fromRGB(120, 214, 255) },
	{ Id = "Breaker", Name = "BREAKER", Smashes = 300, Color = Color3.fromRGB(102, 226, 148) },
	{ Id = "Crusher", Name = "CRUSHER", Smashes = 1500, Color = Color3.fromRGB(255, 206, 84) },
	{ Id = "Destroyer", Name = "DESTROYER", Smashes = 6000, Color = Color3.fromRGB(255, 126, 219) },
	{ Id = "Legend", Name = "LEGEND", Smashes = 25000, Color = Color3.fromRGB(176, 150, 255) },
	{ Id = "Omega", Name = "OMEGA", Smashes = 100000, Color = Color3.fromRGB(255, 90, 90) },
}

-- Rebirth ------------------------------------------------------------------
Config.Rebirth = {
	BaseCost = 9690000000, -- cena prvního rebirthu (~3 h, změřeno simulací)
	Growth = 7.5,
	RequiredWorld = 2, -- kolik světů musí být odemčeno
	BonusPerRebirth = 0.5, -- +50 % k Poweru i penězům, natrvalo
	GemsPerRebirth = 25,
}

-- Odměny ------------------------------------------------------------------
Config.Rewards = {
	FreeChestCooldown = 90, -- sekundy mezi zdarma truhlami
	FreeChestSeconds = 45, -- truhla dá tolik sekund tvého aktuálního příjmu
	OfflineCapHours = 8, -- víc než 8 h offline se nepočítá
	OfflineRate = 0.35, -- offline vydělává 35 % normálního příjmu
}

-- Vzhled -------------------------------------------------------------------
--[[
	Paleta vychází ze dvou věcí naráz:

	  * z toho, jak vypadají největší hry v žánru — sytá fialová panelová
	    základna, tmavý obrys na všem, zlaté peníze, magenta akcenty,
	  * z barevných trendů 2026 — hyper-violet, acid green a "crystalline
	    blue" jako neonové akcenty na tmavém podkladu, holografické pastely
	    na plochách.

	Držet obojí najednou jde: trendové akcenty sedí přesně na role, které
	žánr potřebuje (Power = crystalline blue, bonusy = acid green,
	prémiové = hyper-violet).
]]
Config.Theme = {
	-- Tmavá základna a obrysy
	Ink = Color3.fromRGB(18, 13, 38),
	Background = Color3.fromRGB(14, 10, 28),
	Outline = Color3.fromRGB(18, 13, 38),

	-- Panely: candy fialová se světlejším horním okrajem
	Panel = Color3.fromRGB(126, 62, 190),
	PanelTop = Color3.fromRGB(172, 100, 232),
	PanelDeep = Color3.fromRGB(84, 38, 138),
	PanelEdge = Color3.fromRGB(222, 172, 255),
	PanelLight = Color3.fromRGB(64, 30, 108),

	-- Trendové akcenty
	Violet = Color3.fromRGB(150, 86, 255),
	Pink = Color3.fromRGB(255, 86, 178),
	Cyan = Color3.fromRGB(96, 226, 255),
	Acid = Color3.fromRGB(168, 255, 88),
	Gold = Color3.fromRGB(255, 196, 60),
	Spicy = Color3.fromRGB(255, 160, 48),
	Accent = Color3.fromRGB(255, 196, 60),

	-- Významové barvy
	Power = Color3.fromRGB(118, 220, 255),
	Coins = Color3.fromRGB(255, 214, 92),
	Gems = Color3.fromRGB(126, 255, 208),
	Success = Color3.fromRGB(122, 240, 148),
	Danger = Color3.fromRGB(255, 74, 92),

	-- Spodní lišta postupu (ta tan/zlatá z referencí)
	BarFill = Color3.fromRGB(214, 174, 118),
	BarDeep = Color3.fromRGB(148, 110, 64),

	Text = Color3.fromRGB(255, 255, 255),
	TextDim = Color3.fromRGB(202, 186, 240),
}

-- Vyhledávače ---------------------------------------------------------------

local function findById(list, id: string)
	for index, entry in list do
		if entry.Id == id then
			return entry, index
		end
	end
	return nil, nil
end

function Config.world(id: string)
	return (findById(Config.Worlds, id))
end

function Config.worldIndex(id: string): number
	local _, index = findById(Config.Worlds, id)
	return index or 1
end

function Config.upgrade(id: string)
	return (findById(Config.Upgrades, id))
end

function Config.boost(id: string)
	return (findById(Config.Boosts, id))
end

-- Povrch, po kterém se chodí: sokl a dlaždice dohromady.
function Config.floorTop(): number
	return Config.Track.BaseHeight + Config.Track.TileHeight
end

function Config.upgradePrice(id: string, level: number): number?
	local upgrade = Config.upgrade(id)
	if not upgrade or level >= upgrade.MaxLevel then
		return nil
	end
	return math.floor(upgrade.BasePrice * upgrade.Growth ^ level)
end

--[[
	Účinek vylepšení na dané úrovni, jak ho má vidět hráč.

	Odvozuje se z `PerLevel`, ne se opisuje: kdyby se čísla psala
	zvlášť, rozešla by se s tím, co vylepšení doopravdy dělá, při první
	úpravě rovnováhy — a hráč by si kupoval něco jiného, než co mu
	řádka slíbila.

	Zaokrouhluje se na celá čísla. "+3.0000000000000004%" je matematicky
	správně a v obchodě to vypadá jako rozbitá hra.
]]
function Config.upgradeEffect(id: string, level: number): string
	local upgrade = Config.upgrade(id)
	if not upgrade then
		return ""
	end

	local value = level * upgrade.PerLevel * (upgrade.Scale or 1)
	local rounded = math.floor(value * 10 + 0.5) / 10
	local text = if rounded == math.floor(rounded)
		then tostring(math.floor(rounded))
		else tostring(rounded)

	return `+{text}{upgrade.Suffix or ""}`
end

-- Kolik Poweru je potřeba na proražení bariéry `index` ve světě `worldIndex`
--[[
	Kolo (lap) = kolikrát už hráč tenhle svět dojel celý.

	Bez něj byla hra rozbitá způsobem, který se pozná jen měřením: svět
	se po dojetí resetuje a hráč ho jede pořád dokola, ale zdi zůstávaly
	stejné. Po pár kolech a pár upgradech byly triviální — simulace
	ukázala, že 99 % bariér padlo dřív, než k nim hráč vůbec doběhl.
	Power, magnet, štěstí i pety tím přestaly cokoliv znamenat a
	na postupu se podílela jedině rychlost běhu.

	Každé kolo proto zvedne jak požadavek, tak výplatu. Výplata roste
	o kousek rychleji, takže postup pokračuje — ale sbírání zůstává tím,
	co hráče brzdí, což je celý smysl téhle hry.
]]
local function lapScale(growth: number, lap: number): number
	return growth ^ math.clamp(lap, 0, Config.Track.LapCap)
end

function Config.barrierPower(worldIndex: number, index: number, lap: number?): number
	local world = Config.Worlds[worldIndex]
	local base = world.Pickup * world.BarrierBase * world.BarrierGrowth ^ (index - 1)
	return math.floor(base * lapScale(Config.Track.LapPower, lap or 0))
end

function Config.barrierCoins(worldIndex: number, index: number, lap: number?): number
	local world = Config.Worlds[worldIndex]
	local base = world.CoinBase * world.CoinGrowth ^ (index - 1)
	return math.floor(base * lapScale(Config.Track.LapCoins, lap or 0))
end

-- Kolikáté kolo hráč zrovna jede (1 = první průjezd, do UI).
function Config.lapOf(profile: any, worldIndex: number): number
	local world = Config.Worlds[worldIndex]
	if not world then
		return 0
	end
	return (profile.Laps and profile.Laps[world.Id]) or 0
end

function Config.rebirthCost(rebirths: number): number
	return math.floor(Config.Rebirth.BaseCost * Config.Rebirth.Growth ^ rebirths)
end

-- Nejvyšší titul, na který má hráč nárok
function Config.titleFor(smashes: number)
	local best = Config.Titles[1]
	for _, title in Config.Titles do
		if smashes >= title.Smashes then
			best = title
		end
	end
	return best
end

return Config

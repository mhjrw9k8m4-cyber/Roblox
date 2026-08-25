--!strict
--[[
	Live — obsah, který se za běhu hry mění: kódy, denní odměny, questy,
	squishy hračky a placené věci.

	Je oddělený od `Config` schválně. Config drží pravidla hry, tohle drží
	obsah, který budeš měnit každý týden — nový kód po videu, nová sezóna
	hraček, jiné denní odměny. Update pak znamená sáhnout do jednoho souboru.

	Proč to tady vůbec je: Roblox v roce 2026 řadí hry podle retence
	(návrat druhý den, návrat do týdne, délka sezení), ne podle počtu hráčů
	online. Všechno v tomhle souboru existuje proto, aby měl hráč důvod
	se vrátit zítra.
]]

local Live = {}

-- Kódy ---------------------------------------------------------------------
--[[
	Uplatnitelné jednou za účet. Přidávej je s každým videem nebo updatem —
	kód je nejlevnější způsob, jak přivést hráče zpátky.

	`Expires` je unixový čas; 0 znamená bez omezení.
]]
Live.Codes = {
	{ Code = "LAUNCH", Coins = 5000, Gems = 50, Expires = 0 },
	{ Code = "SMASH", Coins = 2500, Gems = 25, Expires = 0 },
	{ Code = "POWER100", Coins = 10000, Gems = 0, Expires = 0 },
	{ Code = "GEMS50", Coins = 0, Gems = 50, Expires = 0 },
	{ Code = "THANKS", Coins = 1000, Gems = 10, Expires = 0 },
}

-- Denní odměny --------------------------------------------------------------
--[[
	Sedmidenní kolotoč. Sedmý den je schválně skokově lepší — to je den,
	kvůli kterému lidi drží streak, a zároveň přesně ten okamžik, který
	rozhoduje o D7 retenci.

	`Coins` je násobek aktuálního příjmu za sekundu, ne pevné číslo.
	Pevná částka by byla v první hodině obrovská a v desáté k ničemu.
]]
Live.Daily = {
	{ Day = 1, CoinSeconds = 30, Gems = 5 },
	{ Day = 2, CoinSeconds = 60, Gems = 8 },
	{ Day = 3, CoinSeconds = 120, Gems = 12 },
	{ Day = 4, CoinSeconds = 200, Gems = 18 },
	{ Day = 5, CoinSeconds = 320, Gems = 25 },
	{ Day = 6, CoinSeconds = 500, Gems = 35 },
	{ Day = 7, CoinSeconds = 900, Gems = 75, Squishy = "Star" },
}

-- Denní úkoly ---------------------------------------------------------------
--[[
	Každý den se vylosují tři. Splnit všechny tři drží questovou sérii,
	která dává gemy navíc — dvě smyčky (denní odměna + úkoly) drží hráče
	líp než jedna.

	`Scale` říká, jestli se cíl škáluje s postupem hráče. Bez toho je
	"seber 200 pickupů" v prvním světě dřina a v šestém nic.
]]
Live.Quests = {
	{ Id = "Smash", Text = "Smash {target} walls", Type = "smash", Base = 12, Scale = 1.0, Gems = 10 },
	{ Id = "Collect", Text = "Collect {target} pickups", Type = "collect", Base = 250, Scale = 1.0, Gems = 10 },
	{ Id = "Clear", Text = "Clear {target} full laps", Type = "clear", Base = 2, Scale = 0.5, Gems = 15 },
	{ Id = "Spend", Text = "Spend {target} coins", Type = "spend", Base = 20, Scale = 0.0, Gems = 12 },
	{ Id = "Squeeze", Text = "Squeeze {target} times", Type = "squeeze", Base = 150, Scale = 0.0, Gems = 15 },
	{ Id = "Upgrade", Text = "Buy {target} upgrades", Type = "upgrade", Base = 5, Scale = 0.0, Gems = 10 },
	--[[
		Úkol na combo cílí na to, co hráč sám od sebe nezkusí: sbírat
		bez zastavení. `Base` je počet článků v jednom řetězu, ne součet —
		sečítat by šlo splnit i pomalým sbíráním, což je přesně naopak.
	]]
	{ Id = "Combo", Text = "Reach a {target} chain", Type = "combo", Base = 40, Scale = 0.2, Gems = 15 },
}

Live.QuestsPerDay = 3
Live.QuestStreakGems = 20 -- bonus za splnění všech tří

-- Squishy hračky -------------------------------------------------------------
--[[
	Squishy je hračka, kterou hráč **drží v ruce**. Mačká se, pomalu se
	vrací do tvaru a při každém zmáčknutí přisype trochu Poweru.

	Proč hračka a ne mazlíček: mazlíček lítá za zády, kde ho hráč nevidí
	a nemůže s ním nic dělat. Hračka je v ruce, uprostřed obrazu, a dá se
	s ní hýbat — je tím pádem součástí hraní, ne jen statistikou.

	Dvě čísla na každé hračce a každé má jinou roli:

	  `Power`   — kolik přidá k násobiči za držení. To je ta pasivní
	              polovina, kvůli které se hráč posouvá dál.
	  `Squeeze` — jaký díl jednoho pickupu dá jedno zmáčknutí. To je ta
	              aktivní polovina: odměna za to, že hráč něco dělá.

	Tvrdší hračky mají vyšší `Power`, ale nižší `Squeeze` — kámen se
	nemačká. Měkké je to naopak. Hráč si tak vybírá styl, ne jen
	"nejdražší je nejlepší".
]]
Live.Grades = {
	Soft = { Name = "Soft", Color = Color3.fromRGB(255, 176, 206), Order = 1 },
	Chewy = { Name = "Chewy", Color = Color3.fromRGB(255, 206, 128), Order = 2 },
	Dense = { Name = "Dense", Color = Color3.fromRGB(120, 226, 255), Order = 3 },
	Jumbo = { Name = "Jumbo", Color = Color3.fromRGB(168, 255, 88), Order = 4 },
	Prime = { Name = "Prime", Color = Color3.fromRGB(255, 86, 178), Order = 5 },
}

--[[
	Ceny jsou v mincích a rostou zhruba stejným tempem jako světy, takže
	je pořád co si přát. `Give` u hraček, které se nedají koupit, je
	odměna — sedmý den v kolotoči, kód, dokončený svět.

	`Shape` a `Color` staví hračku procedurálně; nic se nenahrává.
	`Softness` řídí, jak hluboko se hračka při zmáčknutí propadne
	(1 = úplně měkká) a jak dlouho se vrací.
]]
--[[
	Katalog hraček.

	Pořadí je zároveň žebříček: každá další je dražší a dává víc.
	A hlavně — pořadí odpovídá pořadí levelů. Level, ve kterém stojí
	obří máslo, prodává máslo; level se sýrem prodává sýr. Do teď to
	tak nebylo: v sedmém levelu stála broskev, která byla nejdražší
	hračka ve hře, a v devátém sýr za tisícinu té ceny. Hráč tím pádem
	viděl u trati věci v náhodném pořadí a "kam až jsem došel" neneslo
	žádnou informaci o tom, co si může dovolit.

	Test `každý level má hračku a žebříček stoupá s levely` to hlídá,
	takže se to znovu rozejít nemůže.
]]
Live.Squishies = {
	{
		Id = "Blob",
		Name = "Pink Blob",
		Grade = "Soft",
		Price = 0,
		Power = 0.12,
		Squeeze = 0.6,
		Softness = 1,
		Shape = "Ball",
		Color = Color3.fromRGB(255, 138, 190),
	},
	--[[
		Marshmallow. Nejlevnější koupená hračka je schválně skoro
		zadarmo: hráč si ji může dovolit ještě v první minutě a tím se
		naučí, že se hračky vůbec kupují.
	]]
	{
		Id = "Foam",
		Name = "Marshmallow",
		Grade = "Soft",
		Price = 2500,
		Power = 0.2,
		Squeeze = 0.62,
		Softness = 0.96,
		Shape = "Block",
		Color = Color3.fromRGB(255, 244, 246),
	},
	--[[
		Máslo v papíru s modrým nápisem. Recept v `Shared.Toy` mu přidá
		obal; tady je jen barva samotné hmoty.

		`Softness` je skoro na maximu schválně — tohle je ta hračka
		z videí, u které jde o "SUPER slow rise". Vrací se nejdéle ze
		všech a chvíli se lepí na prst.
	]]
	{
		Id = "Butter",
		Name = "Salted Butter",
		Grade = "Soft",
		Price = 30000,
		Power = 0.3,
		Squeeze = 0.58,
		Softness = 0.98,
		Shape = "Block",
		Color = Color3.fromRGB(250, 236, 168),
	},
	{
		Id = "Mochi",
		Name = "Mochi Bun",
		Grade = "Chewy",
		Price = 900000,
		Power = 0.8,
		Squeeze = 0.5,
		Softness = 0.9,
		Shape = "Ball",
		Color = Color3.fromRGB(255, 246, 240),
	},
	--[[
		Želé. Jediná průhledná hračka v katalogu — v ruce se skrz ni
		dá vidět a v Jelly Deep, odkud pochází, to sedí na podlahu.
	]]
	{
		Id = "Jelly",
		Name = "Jelly Cube",
		Grade = "Chewy",
		Price = 5000000,
		Power = 1.2,
		Squeeze = 0.52,
		Softness = 0.88,
		Shape = "Block",
		Color = Color3.fromRGB(255, 96, 128),
	},
	{
		Id = "Donut",
		Name = "Glazed Donut",
		Grade = "Chewy",
		Price = 18000000,
		Power = 1.6,
		Squeeze = 0.45,
		Softness = 0.8,
		Shape = "Cylinder",
		Color = Color3.fromRGB(255, 176, 128),
	},
	{
		Id = "Peach",
		Name = "Jumbo Peach",
		Grade = "Dense",
		Price = 420000000,
		Power = 3.4,
		Squeeze = 0.44,
		Softness = 0.78,
		Shape = "Ball",
		Color = Color3.fromRGB(255, 168, 148),
	},
	{
		Id = "Loaf",
		Name = "Jumbo Loaf",
		Grade = "Dense",
		Price = 9000000000,
		Power = 6.5,
		Squeeze = 0.42,
		Softness = 0.74,
		Shape = "Block",
		Color = Color3.fromRGB(255, 224, 196),
	},
	--[[
		Sýr s dírami. Druhá hračka z referencí: prst do něj udělá dolík
		vedle jedné z děr a ten dolík tam chvíli zůstane.
	]]
	{
		Id = "Cheese",
		Name = "Cheese Cube",
		Grade = "Jumbo",
		Price = 260000000000,
		Power = 13,
		Squeeze = 0.4,
		Softness = 0.7,
		Shape = "Block",
		Color = Color3.fromRGB(250, 232, 150),
	},
	--[[
		Cukrový krystal. Tvrdá hračka, která patří k Sugar Glass:
		skoro se nemačká, ale za držení dává hodně. Katalog potřebuje
		i tuhle stranu, jinak je volba mezi hračkami jen "ta dražší".
	]]
	{
		Id = "Candy",
		Name = "Rock Candy",
		Grade = "Jumbo",
		Price = 7000000000000,
		Power = 26,
		Squeeze = 0.24,
		Softness = 0.32,
		Shape = "Block",
		Color = Color3.fromRGB(150, 236, 255),
	},
	{
		Id = "Ball",
		Name = "Chrome Ball",
		Grade = "Prime",
		Price = 180000000000000,
		Power = 40,
		Squeeze = 0.22,
		Softness = 0.3,
		Shape = "Ball",
		Color = Color3.fromRGB(226, 234, 250),
	},
	--[[
		Poslední dvě se nekupují. Jedna je za sedmý den v kolotoči,
		druhá za dokončení posledního světa — musí zůstat něco, co si
		hráč nemůže jen koupit, jinak nemá cenu nikam dojít.
	]]
	{
		Id = "Star",
		Name = "Lucky Star",
		Grade = "Prime",
		Price = 0,
		Power = 9,
		Squeeze = 0.9,
		Softness = 1,
		Shape = "Ball",
		Color = Color3.fromRGB(255, 196, 60),
	},
	{
		Id = "Core",
		Name = "Void Core",
		Grade = "Prime",
		Price = 0,
		Power = 60,
		Squeeze = 0.35,
		Softness = 0.5,
		Shape = "Ball",
		Color = Color3.fromRGB(178, 140, 255),
	},
}

-- Kolik jich hráč unese naráz. První je v ruce, zbytek visí na pásku.
Live.MaxHeld = 3
Live.MaxHeldVip = 6

--[[
	Kolikrát za sekundu se dá zmáčknout. Bez stropu by makro udělalo
	z hračky nekonečný zdroj; se stropem je to odměna za pozornost.
]]
Live.SqueezeRate = 5

-- Placené věci ----------------------------------------------------------------
--[[
	ID jsou nuly — doplň je, až gamepassy a produkty vytvoříš na
	Creator Dashboardu. Dokud je tam nula, tlačítka se v UI nezobrazí,
	takže hra funguje i bez nich a nikomu neukazuje mrtvé nabídky.
]]
-- Denní nabídka -------------------------------------------------------------
--[[
	Jeden boost denně se slevou. Stejný pro celý server, protože se
	odvozuje z čísla dne — není co ukládat, není co replikovat a dva
	hráči vedle sebe vidí totéž.

	Sleva je schválně na boostech, ne na vylepšeních: vylepšení jsou
	trvalá a sleva na nich by rozhodila ekonomiku napořád. Boost vyprchá.
]]
--[[
	Dvojnásobek pro celý server.

	V referenčních hrách visí nahoře "x2 WINS" a je to jediná věc, která
	na obrazovce bliká sama od sebe — hráč se kvůli ní vrací a v tu chvíli
	hraje jinak, protože se mu vyplatí spěchat.

	Nic se neukládá a nic nereplikuje: okno se počítá z času serveru,
	takže na něm všichni nezávisle vyjdou stejně. Ta samá úvaha jako
	u denní slevy — stav, který se dá dopočítat, se nemá ukládat.
]]
Live.Happy = {
	-- Jak často okno začíná a jak dlouho trvá (v sekundách)
	EverySeconds = 1800,
	LengthSeconds = 300,
	-- Násobek mincí po tu dobu
	Coins = 2,
}

Live.Deal = {
	Discount = 0.4, -- 40 % dolů
	-- Pořadí, ve kterém se boosty střídají. Kratší než počet boostů být
	-- může; delší ne — pak by některý nikdy nepřišel na řadu.
	Rotation = { "Power2", "Coins2", "Auto" },
}

-- Který boost je dnes v akci. `day` je celé číslo dne (unix / 86400).
function Live.dealOf(day: number): string
	local order = Live.Deal.Rotation
	return order[day % #order + 1]
end

-- Směna gemů ----------------------------------------------------------------
--[[
	Gemy se dají vyměnit za mince. Kurz není pevné číslo, ale násobek
	hráčova příjmu za sekundu — pevná částka by byla za hodinu hraní
	směšná a pro nového hráče nedosažitelná.
]]
Live.Exchange = {
	Gems = 10, -- kolik gemů jedna směna stojí
	Seconds = 900, -- kolik sekund příjmu za ně hráč dostane
}

Live.Passes = {
	{ Id = "Coins2", Name = "×2 Coins", Desc = "Double coins forever.", GamepassId = 0, Icon = "💰" },
	{ Id = "AutoCollect", Name = "Auto Collect", Desc = "Collects pickups for you, forever.", GamepassId = 0, Icon = "🤖" },
	{ Id = "Vip", Name = "VIP", Desc = "6 squishy slots, +50% power, VIP tag.", GamepassId = 0, Icon = "👑" },
	{ Id = "Grip", Name = "Iron Grip", Desc = "Every squeeze counts double.", GamepassId = 0, Icon = "🤜" },
}

Live.Products = {
	{ Id = "Gems100", Name = "100 Gems", Gems = 100, ProductId = 0, Icon = "💎" },
	{ Id = "Gems550", Name = "550 Gems", Gems = 550, ProductId = 0, Icon = "💎" },
	{ Id = "CoinsSmall", Name = "Coin Boost", CoinSeconds = 600, ProductId = 0, Icon = "💰" },
	{ Id = "CoinsBig", Name = "Big Coin Boost", CoinSeconds = 3600, ProductId = 0, Icon = "💰" },
}

-- Bonusy z pasů, které se počítají do ekonomiky
Live.PassBonus = {
	Coins2 = 2, -- násobič peněz
	Vip = 1.5, -- násobič Poweru
	Grip = 2, -- násobič síly jednoho zmáčknutí
}

-- Obří zeď ----------------------------------------------------------------------
--[[
	Serverová událost. Uprostřed hubu stojí zeď, na kterou mlátí všichni
	naráz, a její stav je společný pro celý server.

	Proč to ve hře je: sólo grind drží hráče do chvíle, než ho omrzí.
	Společný cíl s odpočtem je důvod zůstat déle a vrátit se — a odměna
	pro celý server z toho dělá věc, o které si lidi napíšou v chatu.

	Odměna se dělí podle podílu na poškození, takže se vyplatí přispět
	i malým dílem, ale nedá se jen přihlížet.
]]
Live.GiantWall = {
	-- Kolik násobků příjmu nejsilnějšího hráče na serveru zeď vydrží
	HealthPerPlayer = 900,
	MinHealth = 250000,
	-- Jak dlouho trvá kolo; po vypršení se zeď obnoví bez odměny
	RoundSeconds = 900,
	-- Pauza mezi koly
	BreakSeconds = 120,
	-- Podíl na odměně: základ pro všechny + zbytek podle příspěvku
	BaseShare = 0.25,
	--[[
		Boost pro celý server po proražení. Jak silný je, se tady
		schválně NEuvádí — uděluje se přes běžné boosty Power2/Coins2
		a jejich násobek je v Config.Boosts. Druhé číslo na druhém místě
		by se dřív nebo později rozešlo s tím, co hra opravdu dělá.
	]]
	BoostSeconds = 180,
	GemsForTop = 25,
	GemsForAll = 5,
}

-- Badge ------------------------------------------------------------------------
-- ID doplň z Creator Dashboardu; nula = badge se prostě neudělí.
Live.Badges = {
	{ Id = "FirstSmash", Name = "First Wall", BadgeId = 0, Smashes = 1 },
	{ Id = "Hundred", Name = "100 Walls", BadgeId = 0, Smashes = 100 },
	{ Id = "Thousand", Name = "1000 Walls", BadgeId = 0, Smashes = 1000 },
	{ Id = "FirstRebirth", Name = "Reborn", BadgeId = 0, Rebirths = 1 },
	{ Id = "WorldThree", Name = "Ice Breaker", BadgeId = 0, Worlds = 3 },
	{ Id = "WorldSix", Name = "Void Walker", BadgeId = 0, Worlds = 6 },
}

-- Vyhledávače --------------------------------------------------------------------

local function findById(list, id: string)
	for index, entry in list do
		if entry.Id == id then
			return entry, index
		end
	end
	return nil, nil
end

function Live.squishy(id: string)
	return (findById(Live.Squishies, id))
end

--[[
	Stupeň hračky. Vrací záznam, ne jen jméno, protože volající skoro
	vždycky chce barvu — a dohledávat ji podruhé je jen další místo,
	kde se to dá splést.
]]
function Live.grade(id: string)
	local squishy = Live.squishy(id)
	local key = if squishy then squishy.Grade else "Soft"
	return Live.Grades[key] or Live.Grades.Soft
end

-- Hračky, které se dají koupit za mince (ostatní jsou odměny)
function Live.forSale()
	local list = {}
	for _, squishy in Live.Squishies do
		if squishy.Price > 0 then
			table.insert(list, squishy)
		end
	end
	return list
end

function Live.pass(id: string)
	return (findById(Live.Passes, id))
end

function Live.product(id: string)
	return (findById(Live.Products, id))
end

function Live.quest(id: string)
	return (findById(Live.Quests, id))
end

-- Kód se porovnává bez ohledu na velikost písmen a okolní mezery
function Live.code(input: string)
	local normalized = string.upper((input:gsub("%s", "")))
	for _, entry in Live.Codes do
		if entry.Code == normalized then
			return entry
		end
	end
	return nil
end

return Live

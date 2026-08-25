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
	--[[
		Řetěz má strop `Combo.Max`, takže cíl musí i v posledním světě
		zůstat pod ním. Při deseti světech a růstu 0,2 vycházel v devátém
		na 104 — server ho sice ořízne, ale od šestého světa dál by byl
		u všech stejný a přestal by růst. 0,15 drží růst přes celou řadu.
	]]
	{ Id = "Combo", Text = "Reach a {target} chain", Type = "combo", Base = 40, Scale = 0.15, Gems = 15 },
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
--[[
	Hračka, se kterou hráč začíná. Bez ní by měl prázdnou ruku a
	mechanika mačkání by pro něj neexistovala, dokud si nenašetří —
	tedy přesně v době, kdy se rozhoduje, jestli hru vůbec bude hrát.
]]
--[[
	Odměny za to, jak dlouho hráč v jednom sezení vydrží.

	Počítá se SEZENÍ, ne odehraný čas celkem — smysl téhle smyčky je
	prodloužit tohle přihlášení, ne odměnit včerejšek. Proto se to taky
	nikam neukládá: po odpojení začíná ladder znovu od nuly.

	Odstupy rostou (5 → 15 → 30 → 60 minut), protože pravidelná odměna
	po stejné době se za hodinu stane pozadím. Rostoucí odstup naopak
	drží "ještě chvilku" pořád na stole.

	Mince se počítají z hráčova vlastního příjmu, ne pevným číslem:
	pevná částka je pro nováčka jmění a pro veterána nula.
]]
Live.Playtime = {
	{ Minutes = 5, IncomeSeconds = 60, Gems = 5 },
	{ Minutes = 15, IncomeSeconds = 180, Gems = 10 },
	{ Minutes = 30, IncomeSeconds = 420, Gems = 20 },
	{ Minutes = 60, IncomeSeconds = 900, Gems = 40 },
}

--[[
	Kolik odměn za sezení hráči náleží po `seconds` sekundách. Vrací
	index nejvyššího dosaženého stupně, tedy 0 pro nováčka v prvních
	pěti minutách.
]]
function Live.playtimeReached(seconds: number): number
	local reached = 0
	for index, tier in Live.Playtime do
		if seconds >= tier.Minutes * 60 then
			reached = index
		end
	end
	return reached
end

--[[
	Hraní s kamarády.

	Roblox od konce roku 2025 řadí hry hlavně podle toho, jestli se hráč
	VRÁTÍ, a jedním z měřených signálů je společné hraní ("Intentional
	Co-Play"). Hra, do které si lidé zvou kamarády, dostane víc míst
	v doporučování než hra se stejným počtem hráčů, kteří sedí každý sám.

	Bonus je proto na mincích, ne na kosmetice: musí být znát hned a musí
	se vyplatit počkat, až se kamarád připojí. Strop je tam, aby ze
	skupiny šesti lidí nebyl jiný řád ekonomiky než ze hry pro jednoho.
]]
Live.Social = {
	-- Kolik přidá jeden kamarád na serveru k mincím
	FriendBonus = 0.25,
	-- Nad tenhle počet už se další kamarád nepočítá
	MaxFriends = 4,
	-- Gemy za kamaráda, který přišel přes tvoje pozvání. Jednou za člověka.
	ReferralGems = 50,

	--[[
		Společný průraz: když stejnou zeď rozbijí dva hráči krátce po
		sobě, dostanou oba navíc.

		Doporučení pro rok 2026 je mít ve hře aspoň jednu věc, která je
		s druhým člověkem opravdu LEPŠÍ — ne jen možná. Bonus za
		přítomnost kamaráda je pasivní; tohle je aktivní: vyplatí se
		běžet spolu a trefit tu samou zeď, ne se rozdělit.

		Okno je krátké schválně. Delší by z toho udělalo "kdokoliv na
		serveru občas", kdežto pár vteřin znamená "běželi jste vedle sebe".
	]]
	TogetherSeconds = 4,
	TogetherBonus = 0.5,
}

--[[
	Varianty hraček.

	Jedna a ta samá hračka může vyjít obyčejná, zlatá nebo duhová.
	Je to nejlevnější způsob, jak z deseti hraček udělat třicet sběratelských
	kusů — model, zvuk ani ekonomika se kvůli tomu nemění, mění se jen
	násobič a barva.

	Proč to funguje: nepravidelná odměna drží pozornost líp než
	pravidelná. Nákup hračky je jistota, ale **jaká** vyjde, jistota
	není — a to je přesně ten okamžik, kvůli kterému hráč zkusí koupit
	znovu.

	Šance jsou schválně takhle: zlatá zhruba jednou z dvanácti, duhová
	zhruba jednou ze sto dvaceti. Duhová se tedy dá čekat, ale ne
	naplánovat, a hráč, který ji má, ji má za co ukazovat.
]]
Live.Variants = {
	{
		Id = "Normal",
		Name = "",
		Icon = "",
		Multiplier = 1,
		Chance = 1,
		Color = Color3.fromRGB(255, 255, 255),
	},
	{
		Id = "Golden",
		Name = "Golden",
		Icon = "⭐",
		Multiplier = 1.6,
		Chance = 0.085,
		Color = Color3.fromRGB(255, 205, 74),
	},
	{
		Id = "Rainbow",
		Name = "Rainbow",
		Icon = "🌈",
		Multiplier = 3,
		Chance = 0.0085,
		Color = Color3.fromRGB(255, 120, 220),
	},
}

--[[
	Kolikrát štěstí zvedne šanci na lepší variantu při plné hodnotě.

	Vylepšení Luck do teď dělalo jen zlaté pickupy. Když má ovlivňovat
	i tohle, musí to být znát, ale ne tak, aby se duhová dala vygrindit
	na jistotu — pak by přestala být vzácná.
]]
Live.VariantLuck = 2

--[[
	Vylosuje variantu z jednoho čísla 0..1.

	Losuje volající, ne tahle funkce: server má vlastní `Random` a test
	potřebuje výsledek, který se nemění. Funkce, která si losuje sama,
	se testovat nedá jinak než stokrát za sebou a doufáním.
]]
function Live.rollVariant(luck: number, roll: number): number
	local boost = 1 + math.clamp(luck, 0, 0.9) * Live.VariantLuck

	--[[
		Od nejvzácnější dolů. Šance jsou vnořené intervaly (duhová leží
		uvnitř zlaté), takže jedno číslo rozhodne obojí — dvě nezávislá
		losování by při vysokém štěstí dala duhovou hračku "obyčejné"
		barvy.
	]]
	for index = #Live.Variants, 2, -1 do
		local variant = Live.Variants[index]
		if roll < math.min(variant.Chance * boost, 0.5) then
			return index
		end
	end

	return 1
end

function Live.variant(index: number?)
	local at = math.clamp(math.floor(index or 1), 1, #Live.Variants)
	return Live.Variants[at]
end

--[[
	Jakou variantu hráč u té hračky má. Chybějící záznam je obyčejná —
	profily z doby před variantami tak nepotřebují žádnou migraci.
]]
function Live.variantOf(profile: any, id: string): number
	local variants = profile.Variants
	if not variants then
		return 1
	end
	return math.clamp(math.floor(variants[id] or 1), 1, #Live.Variants)
end

--[[
	Jméno hračky i s variantou. Na jednom místě proto, že se ukazuje
	v panelu, v hlášce po nákupu i v obchodu.
]]
function Live.variantName(index: number, name: string): string
	local variant = Live.variant(index)
	if variant.Name == "" then
		return name
	end
	return `{variant.Icon} {variant.Name} {name}`
end

Live.Starter = "Blob"

--[[
	Hračka za dokončení posledního světa.

	Jediná cesta, jak se k ní dostat — nekupuje se a v denním kolotoči
	není. Je to schválně data, ne odvození z posledního levelu: kdyby
	se to počítalo, nikdo by při přerovnání levelů nepoznal, že se tím
	mění i odměna za projití celé hry.

	Void Core mimochodem do teď nešel získat vůbec. V katalogu byl,
	recept měl, v posledním levelu stál jako obří rekvizita — a žádný
	kód ho neuděloval.
]]
Live.FinalReward = "Core"

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

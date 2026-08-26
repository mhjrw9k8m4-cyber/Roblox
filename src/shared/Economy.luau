--!strict
--[[
	Economy — všechny vzorce progrese na jednom místě.

	Sdílené záměrně: server podle nich počítá skutečné odměny, klient podle
	nich ukazuje v obchodě, co ti vylepšení přinese. Jeden vzorec = UI nikdy
	nelže o tom, co se stane po nákupu.
]]

local Config = require(script.Parent.Config)
local Live = require(script.Parent.Live)
local Perks = require(script.Parent.Perks)
local Combo = require(script.Parent.Combo)
local Track = require(script.Parent.Track)

local Economy = {}

--[[
	Kolik "kroků" vylepšení hráč doopravdy má.

	Není to počet koupených úrovní: každá desátá se počítá dvakrát
	(viz `Config.upgradeSteps`). Prochází tím každý účinek ve hře, aby
	se milník nemohl propsat jen do některých — a hlavně aby se
	nerozešel s tím, co slibuje obchod.
]]
local function upgradeLevel(profile: any, id: string): number
	return Config.upgradeSteps((profile.Upgrades and profile.Upgrades[id]) or 0)
end

-- Aktivní boosty ------------------------------------------------------------
-- Boost je uložený jako čas vypršení; prošlý se prostě přestane počítat,
-- takže není potřeba nic uklízet.

function Economy.boostMultiplier(profile: any, field: string, now: number): number
	local best = 1

	for _, boost in Config.Boosts do
		if boost.Field == field then
			local expires = profile.Boosts and profile.Boosts[boost.Id]
			if expires and expires > now and boost.Value > best then
				best = boost.Value
			end
		end
	end

	return best
end

function Economy.boostRemaining(profile: any, boostId: string, now: number): number
	local expires = profile.Boosts and profile.Boosts[boostId]
	if not expires then
		return 0
	end
	return math.max(expires - now, 0)
end

-- Násobiče -----------------------------------------------------------------

function Economy.rebirthMultiplier(profile: any): number
	-- Perk "Compound" zvedá to, co dá KAŽDÝ rebirth — i ty už proběhlé.
	-- Je to jediná větev, která se sama znásobuje, proto je nejdražší.
	local perRebirth = Config.Rebirth.BonusPerRebirth + Perks.value(profile, "Rebirth")
	return 1 + profile.Rebirths * perRebirth
end

--[[
	Násobič od squishy hraček, které má hráč u sebe. Bonusy se sčítají
	(dvě hračky po +30 % dají +60 %), VIP pak výsledek ještě přenásobí.

	Počítá se tady, ve sdíleném modulu, aby klient v UI ukazoval přesně
	to samé číslo, jaké server použije při výpočtu.
]]
--[[
	Sbírka: kolik hráč má hraček, kolik z nich je zlatých a kolik
	duhových.

	Duhová se počítá i do zlatých. Kdyby ne, přišel by hráč milníkem
	"najdi tři zlaté" o kus, který je vzácnější než to, co se po něm
	chce — a to je přesně ten druh pravidla, kvůli kterému lidi hru
	přestanou brát vážně.
]]
export type Collection = { owned: number, golden: number, rainbow: number }

function Economy.collection(profile: any): Collection
	local owned, golden, rainbow = 0, 0, 0

	for _, squishy in Live.Squishies do
		if ((profile.Squishies or {})[squishy.Id] or 0) <= 0 then
			continue
		end

		owned += 1
		local variant = Live.variantOf(profile, squishy.Id)
		if variant >= 2 then
			golden += 1
		end
		if variant >= 3 then
			rainbow += 1
		end
	end

	return { owned = owned, golden = golden, rainbow = rainbow }
end

function Economy.collectionProgress(profile: any, entry: any): (number, number)
	local counts = Economy.collection(profile)
	local have = (counts :: any)[entry.Kind] or 0
	return have, Live.collectionTarget(entry)
end

function Economy.canClaimCollection(profile: any, id: string): (boolean, string?)
	local entry = Live.collectionEntry(id)
	if not entry then
		return false, "Unknown milestone."
	end
	if (profile.Collection or {})[id] then
		return false, "Already claimed."
	end

	local have, target = Economy.collectionProgress(profile, entry)
	if have < target then
		return false, "Not there yet."
	end

	return true, nil
end

--[[
	Trvalý bonus za vyzvednuté milníky sbírky.

	Počítá se z vyzvednutých, ne ze splněných: jinak by odměna přišla
	sama a hráč by o ní nevěděl. Kliknutí je to, co z milníku dělá
	okamžik.
]]
function Economy.collectionBonus(profile: any): number
	local total = 1

	for _, entry in Live.Collection do
		if (profile.Collection or {})[entry.Id] then
			total += entry.Bonus
		end
	end

	return total
end

function Economy.squishMultiplier(profile: any): number
	local total = 1

	for _, id in profile.Held or {} do
		local squishy = Live.squishy(id)
		if squishy then
			-- Zlatá a duhová varianta té samé hračky dává víc; viz `Live.Variants`
			total += squishy.Power * Live.variant(Live.variantOf(profile, id)).Multiplier
		end
	end

	if profile.Passes and profile.Passes.Vip then
		total *= Live.PassBonus.Vip
	end

	--[[
		Sbírka násobí až úplně nakonec. Přičítat ji k jednotlivým
		hračkám by znamenalo, že sběratel s jednou hračkou v ruce má
		z bonusu víc než sběratel se třemi — přesně naopak, než jak to
		má být.
	]]
	return total * Economy.collectionBonus(profile)
end

--[[
	Kolik Poweru dá jedno zmáčknutí hračky v ruce.

	Je to podíl jednoho pickupu, ne pevné číslo — jinak by mačkání bylo
	v první hodině všechno a v desáté nic. Počítá se z hračky **v ruce**
	(první v pořadí), protože zmáčknout se dá jen ta, kterou hráč drží.

	Vrací nulu, když hráč nedrží nic; volající pak nemusí nic řešit.
]]
function Economy.squeezeValue(profile: any, now: number): number
	local held = (profile.Held or {})[1]
	local squishy = if held then Live.squishy(held) else nil
	if not squishy then
		return 0
	end

	--[[
		Pořadí: vylepšení, pak spodní hranice, teprve pak pas.

		Obráceně to nefungovalo: na začátku hry vyjde podíl pickupu pod
		jedničku, spodní hranice ho zvedne na jedna — a to samé udělá
		i se zdvojnásobenou hodnotou. Kdo si Iron Grip koupil v první
		hodině, nedostal za něj nic a nešlo to nijak poznat.

		Ze stejného důvodu se před hranici počítá i "Grip Strength":
		po ní by hranice koupené úrovně smázla stejně, jako by tam
		nebyly.
	]]
	local squeeze = Config.upgrade("Squeeze")
	local strength = 1 + upgradeLevel(profile, "Squeeze") * squeeze.PerLevel

	--[[
		Varianta se počítá před hranicí ze stejného důvodu jako
		"Grip Strength": po ní by hranice rozdíl mezi obyčejnou
		a duhovou hračkou smázla přesně tam, kde ho hráč vyhrál.
	]]
	local variant = Live.variant(Live.variantOf(profile, held)).Multiplier

	local base = math.max(
		math.floor(Economy.pickupValue(profile, now) * squishy.Squeeze * strength * variant),
		1
	)
	local grip = if profile.Passes and profile.Passes.Grip then Live.PassBonus.Grip else 1

	return base * grip
end

-- Násobič peněz z gamepassu
function Economy.passCoinMultiplier(profile: any): number
	return if profile.Passes and profile.Passes.Coins2 then Live.PassBonus.Coins2 else 1
end

-- Hodnota jednoho sebraného "+1"
function Economy.pickupValue(profile: any, now: number): number
	local world = Config.Worlds[profile.WorldIndex] or Config.Worlds[1]
	local upgrade = Config.upgrade("Power")

	local fromUpgrade = 1 + upgradeLevel(profile, "Power") * upgrade.PerLevel
	local total = world.Pickup
		* fromUpgrade
		* Economy.rebirthMultiplier(profile)
		* Economy.squishMultiplier(profile)
		* Economy.boostMultiplier(profile, "Power", now)

	return math.max(math.floor(total), 1)
end

--[[
	Běží zrovna dvojnásobek pro celý server?

	Počítá se z času, ne ze stavu. Nic se neukládá, nic nereplikuje
	a dva servery ani klient a server se nemůžou rozejít — to je celý
	důvod, proč je to zbytek dělení a ne proměnná.
]]
function Economy.happyRemaining(now: number): number
	local into = now % Live.Happy.EverySeconds
	if into >= Live.Happy.LengthSeconds then
		return 0
	end
	return Live.Happy.LengthSeconds - into
end

function Economy.happyMultiplier(now: number): number
	return if Economy.happyRemaining(now) > 0 then Live.Happy.Coins else 1
end

--[[
	Bonus za kamarády na serveru.

	`profile.Friends` drží server v paměti a nikam ho neukládá — je to
	stav serveru, ne majetek hráče. Kdyby se ukládal, nesl by si ho hráč
	na prázdný server a bonus za společné hraní by platil i pro toho,
	kdo hraje sám.
]]
function Economy.friendMultiplier(profile: any): number
	local friends = math.clamp(profile.Friends or 0, 0, Live.Social.MaxFriends)
	return 1 + friends * Live.Social.FriendBonus
end

function Economy.coinMultiplier(profile: any, now: number): number
	return Economy.rebirthMultiplier(profile)
		* Economy.passCoinMultiplier(profile)
		* Economy.boostMultiplier(profile, "Coins", now)
		* Economy.happyMultiplier(now)
		* Economy.friendMultiplier(profile)
end

-- Nálet po silném průrazu ----------------------------------------------------
--[[
	`surgeUntil` je čas vypršení. Drží ho server v paměti (ne v profilu):
	trvá pár vteřin, takže by se do DataStore stejně nestihl propsat
	a jen by přidal zápisy navíc.

	Obě funkce níž ho berou jako nepovinný parametr, aby šlo spočítat
	i "jaká by byla rychlost bez náletu" — to potřebuje klient, když
	má nálet doběhnout.
]]
function Economy.surgeActive(surgeUntil: number?, now: number): boolean
	return surgeUntil ~= nil and surgeUntil > now
end

--[[
	Vyvolá průraz nálet? Rozhoduje řetěz comba v okamžiku průrazu, ne
	přeplácnutí — viz Config.Track.SurgeAt.

	Sdílené, aby klient ukázal totéž, co server uzná.
]]
function Economy.surgeTriggered(chain: number): boolean
	return chain >= Config.Track.SurgeAt
end

function Economy.collectRadius(profile: any, surgeUntil: number?, now: number?): number
	local upgrade = Config.upgrade("Magnet")
	local radius = Config.Track.CollectRadius + upgradeLevel(profile, "Magnet") * upgrade.PerLevel

	if Economy.surgeActive(surgeUntil, now or os.time()) then
		radius *= Config.Track.SurgeRadius
	end

	return radius
end

function Economy.walkSpeed(profile: any, surgeUntil: number?, now: number?): number
	local upgrade = Config.upgrade("Speed")
	local speed = 16 + upgradeLevel(profile, "Speed") * upgrade.PerLevel

	if Economy.surgeActive(surgeUntil, now or os.time()) then
		speed *= Config.Track.SurgeSpeed
	end

	return speed
end

function Economy.luckChance(profile: any): number
	local upgrade = Config.upgrade("Luck")
	local total = upgradeLevel(profile, "Luck") * upgrade.PerLevel + Perks.value(profile, "Luck")
	return math.min(total, 0.9)
end

function Economy.autoRate(profile: any, now: number): number
	local upgrade = Config.upgrade("Auto")
	local fromUpgrade = upgradeLevel(profile, "Auto") * upgrade.PerLevel
	local fromBoost = Economy.boostMultiplier(profile, "Auto", now)

	-- Gamepass dává auto-collect natrvalo, i bez upgradu
	if profile.Passes and profile.Passes.AutoCollect then
		fromUpgrade = math.max(fromUpgrade, 4)
	end
	-- boost "Auto" je pevná hodnota, ne násobič — bez upgradu má sám o sobě smysl
	return math.max(fromUpgrade, if fromBoost > 1 then fromBoost else 0)
end

-- Bariéry -------------------------------------------------------------------
--[[
	Požadavek i výplata bariéry závisí na tom, pokolikáté hráč svět jede.
	Všechno proto vede přes tyhle dvě funkce, aby se kolo nedalo nikde
	zapomenout — jednou zapomenuté by znamenalo, že klient ukazuje jiné
	číslo, než jaké server vyžaduje.
]]
function Economy.lap(profile: any, worldIndex: number?): number
	return Config.lapOf(profile, worldIndex or profile.WorldIndex)
end

function Economy.barrierPower(profile: any, barrierIndex: number, worldIndex: number?): number
	local index = worldIndex or profile.WorldIndex
	return Config.barrierPower(index, barrierIndex, Economy.lap(profile, index))
end

function Economy.barrierCoins(profile: any, barrierIndex: number, worldIndex: number?): number
	local index = worldIndex or profile.WorldIndex
	return Config.barrierCoins(index, barrierIndex, Economy.lap(profile, index))
end

--[[
	Bonus za přeplácnutí: kolikrát víc Poweru hráč u zdi nastřádal, než
	kolik potřeboval. Viz Config.Track.OverkillCap — je to jediná cesta,
	kterou se Power, pety, štěstí a combo propisují do peněz i ve chvíli,
	kdy zdi padají samy od sebe.
]]
function Economy.overkill(power: number, required: number, profile: any?): number
	if required <= 0 then
		return 1
	end

	local curve = Config.Track.OverkillCurve
	if profile then
		curve += Perks.value(profile, "Overkill")
	end

	local ratio = math.clamp(power / required, 1, Config.Track.OverkillCap)
	return ratio ^ curve
end

-- Kolik sekund vydrží řetěz; perk "Flow State" okno prodlužuje.
function Economy.comboWindow(profile: any): number
	--[[
		Okno drží dvě věci: koupené vylepšení a perk za rebirth. Perk byl
		do teď jediná cesta, jak si řetěz prodloužit — tedy něco, k čemu
		se nováček nedostane, přestože combo musí pochopit hned.
	]]
	local upgrade = Config.upgrade("Chain")
	local fromUpgrade = upgradeLevel(profile, "Chain") * upgrade.PerLevel

	return Combo.Window + fromUpgrade + Perks.value(profile, "Combo")
end

-- Gemy za dokončené kolo světa: základ světa plus perk "Prospector".
function Economy.clearGems(profile: any, worldIndex: number): number
	local world = Config.Worlds[worldIndex]
	local base = if world then world.Gems else 1
	return base + Perks.value(profile, "Gem")
end

-- Peníze za proražení bariéry. Gemy se za jednotlivé bariéry nedávají,
-- ty padají až za dokončené kolo (viz GameService.worldCleared).
--[[
	Mince za proražení zdi.

	`power` se dá předat zvlášť ze stejného důvodu jako u
	`barrierProgress`: Power chodí ke klientovi vlastním, mnohem
	častějším remotem než celý profil, takže cedule na zdi zná novější
	číslo než profil. Kdyby si ho dopočítávala sama, slíbila by jinou
	částku, než jakou server vzápětí připíše.
]]
function Economy.smashReward(profile: any, barrierIndex: number, now: number, power: number?): number
	local required = Economy.barrierPower(profile, barrierIndex)
	local bonus = Economy.overkill(power or profile.Power or 0, required, profile)

	--[[
		Šťastná zeď platí několikanásobek. Klient i server si ji spočítají
		ze stejného čísla, takže cedule na zdi slibuje přesně to, co
		vzápětí přijde — a hráč nemusí věřit, že se mu to nezdálo.
	]]
	local jackpot = if Track.isJackpot(profile.WorldIndex, Economy.lap(profile), barrierIndex)
		then Config.Track.JackpotMultiplier
		else 1

	return math.floor(
		Economy.barrierCoins(profile, barrierIndex)
			* Economy.coinMultiplier(profile, now)
			* bonus
			* jackpot
	)
end

--[[
	Odhad příjmu za sekundu. Používá se pro truhlu, offline výdělky
	a pro porovnání vylepšení v obchodě, takže musí být konzervativní:
	počítá s tím, že hráč jde tratí plynule a sbírá, na co dosáhne.
]]
function Economy.coinsPerSecond(profile: any, now: number): number
	local worldIndex = profile.WorldIndex
	local barrier = math.clamp(profile.Barrier, 1, Config.Track.BarrierCount)

	local pickup = Economy.pickupValue(profile, now)
	local needed = Economy.barrierPower(profile, barrier, worldIndex)
	local pickupsNeeded = math.max(needed / pickup, 1)

	-- kolik pickupů hráč stihne za sekundu: běh přes segment + respawn
	local perSecond = 2 + Economy.autoRate(profile, now)
	local seconds = math.max(pickupsNeeded / perSecond, 1)

	local coins = Economy.barrierCoins(profile, barrier, worldIndex) * Economy.coinMultiplier(profile, now)
	return coins / seconds
end

-- Podmínky nákupů -----------------------------------------------------------

function Economy.canBuyUpgrade(profile: any, id: string): (boolean, string?)
	local upgrade = Config.upgrade(id)
	if not upgrade then
		return false, "Unknown upgrade."
	end

	local price = Config.upgradePrice(id, upgradeLevel(profile, id))
	if not price then
		return false, "Max level reached."
	end
	if profile.Coins < price then
		return false, "Not enough coins."
	end

	return true, nil
end

function Economy.canBuyWorld(profile: any, id: string): (boolean, string?)
	local world = Config.world(id)
	if not world then
		return false, "Unknown world."
	end
	if profile.Worlds[id] then
		return false, "Already unlocked."
	end

	-- Světy se odemykají po pořadě, jinak by šel přeskočit celý grind
	local index = Config.worldIndex(id)
	if index > 1 then
		local previous = Config.Worlds[index - 1]
		if not profile.Worlds[previous.Id] then
			return false, `Unlock {previous.Name} first.`
		end
	end

	if profile.Coins < world.Price then
		return false, "Not enough coins."
	end

	return true, nil
end

-- Denní nabídka a směna ------------------------------------------------------

-- Číslo dne, ze kterého se odvozuje denní sleva. Sdílené, aby klient
-- ukazoval stejnou nabídku, jakou server uzná.
function Economy.day(now: number): number
	return math.floor(now / 86400)
end

function Economy.dealId(now: number): string
	return Live.dealOf(Economy.day(now))
end

-- Cena boostu v gemech po případné denní slevě.
function Economy.boostPrice(id: string, now: number): number
	local boost = Config.boost(id)
	if not boost then
		return 0
	end

	if Economy.dealId(now) == id then
		return math.max(math.ceil(boost.Gems * (1 - Live.Deal.Discount)), 1)
	end

	return boost.Gems
end

--[[
	Kolik mincí hráč dostane za jednu směnu gemů.

	Kurz je násobek příjmu za sekundu, ne pevná částka: pevné číslo by
	bylo po hodině hraní směšné a pro nového hráče nedosažitelné.
]]
function Economy.exchangeValue(profile: any, now: number): number
	return math.floor(Economy.coinsPerSecond(profile, now) * Live.Exchange.Seconds)
end

function Economy.canExchange(profile: any): (boolean, string?)
	if (profile.Gems or 0) < Live.Exchange.Gems then
		return false, "Not enough gems."
	end
	return true, nil
end

function Economy.canBuyBoost(profile: any, id: string, now: number?): (boolean, string?)
	local boost = Config.boost(id)
	if not boost then
		return false, "Unknown boost."
	end
	if profile.Gems < Economy.boostPrice(id, now or os.time()) then
		return false, "Not enough gems."
	end
	return true, nil
end

function Economy.canRebirth(profile: any): (boolean, string?)
	local unlocked = 0
	for _, world in Config.Worlds do
		if profile.Worlds[world.Id] then
			unlocked += 1
		end
	end

	if unlocked < Config.Rebirth.RequiredWorld then
		return false, `Unlock {Config.Rebirth.RequiredWorld} worlds first.`
	end

	local cost = Config.rebirthCost(profile.Rebirths)
	if profile.Coins < cost then
		return false, "Not enough coins."
	end

	return true, nil
end

function Economy.canClaimChest(profile: any, now: number): (boolean, number)
	local ready = (profile.NextChestAt or 0)
	if now >= ready then
		return true, 0
	end
	return false, ready - now
end

--[[
	Co na hráče čeká k vyzvednutí.

	Odznak u tlačítka je nejsilnější věc, jakou má hra na to, aby si
	hráče přitáhla zpátky do menu — a přitom nic neslibuje navíc: říká
	jen, že tam něco JE. Hráč, který o volné truhle neví, si ji
	nevezme, a odměna, kterou si nikdo nevezme, je stejná jako žádná.

	Počítá se tady, ve sdíleném modulu, aby odznak nikdy nesvítil
	u něčeho, co server odmítne — a hlavně aby nezhasl u něčeho, co by
	pustil.
]]
export type Badges = {
	chest: boolean,
	upgrades: boolean,
	squishies: boolean,
	rebirth: boolean,
	worlds: boolean,
	collection: boolean,
}

function Economy.badges(profile: any, now: number): Badges
	--[[
		Vylepšení: svítí, jakmile si hráč může koupit aspoň jedno.
		Nejde o to nutit ho utrácet — jde o to, aby si všiml, že
		nasbírané mince někde leží nevyužité.
	]]
	local upgrades = false
	for _, upgrade in Config.Upgrades do
		local price = Config.upgradePrice(upgrade.Id, (profile.Upgrades or {})[upgrade.Id] or 0)
		if price and profile.Coins >= price then
			upgrades = true
			break
		end
	end

	-- Hračka, na kterou hráč má a ještě ji nemá
	local squishies = false
	for _, squishy in Live.forSale() do
		if (profile.Squishies or {})[squishy.Id] == nil and profile.Coins >= squishy.Price then
			squishies = true
			break
		end
	end

	-- Další svět, na který si našetřil
	local worlds = false
	for _, world in Config.Worlds do
		if not (profile.Worlds or {})[world.Id] and profile.Coins >= world.Price then
			worlds = true
			break
		end
	end

	--[[
		Splněný milník sbírky, který si hráč ještě nevzal. Sbírka se
		plní sama tím, že hráč hraje, takže o splnění nemá jak vědět —
		bez odznaku by mu odměna ležela měsíce.
	]]
	local collection = false
	for _, entry in Live.Collection do
		if (Economy.canClaimCollection(profile, entry.Id)) then
			collection = true
			break
		end
	end

	return {
		chest = (Economy.canClaimChest(profile, now)),
		upgrades = upgrades,
		squishies = squishies,
		worlds = worlds,
		collection = collection,
		--[[
			Rebirth svítí ze dvou důvodů: buď na něj hráč má, nebo mu
			leží nevyužitý token za ten minulý. Nevyužitý token je horší
			z těch dvou — hráč si rebirth odbyl a odměna za něj zůstala
			ležet.
		]]
		rebirth = (Economy.canRebirth(profile)) or Perks.available(profile) > 0,
	}
end

--[[
	Nejbližší věc, kterou si hráč může odemknout.

	Spodní pruh ukazuje jen zeď, na které hráč zrovna stojí — to je
	horizont pár vteřin. Po průrazu se ale nemá na co dívat: mince
	přibývají a nic neříká, k čemu vlastně jsou.

	Vybírá se ta **nejbližší** meta, ne nejdražší. Cíl, o kterém je
	vidět, že se blíží, táhne; cíl na dva dny dopředu odrazuje.
]]
export type Goal = {
	Kind: string,
	Id: string,
	Name: string,
	Icon: string,
	Price: number,
	Progress: number,
	Ready: boolean,
}

function Economy.nextGoal(profile: any): Goal?
	local best: Goal? = nil
	local bestProgress = -1

	local function consider(goal: Goal)
		-- Zdarma není meta; první svět i startovní hračka mají cenu 0
		if goal.Price <= 0 then
			return
		end
		if goal.Progress > bestProgress then
			best = goal
			bestProgress = goal.Progress
		end
	end

	local coins = profile.Coins or 0

	local owned = profile.Squishies or {}
	local cheapest = nil
	for _, squishy in Live.forSale() do
		if owned[squishy.Id] == nil and (cheapest == nil or squishy.Price < cheapest.Price) then
			cheapest = squishy
		end
	end
	if cheapest then
		consider({
			Kind = "squishy",
			Id = cheapest.Id,
			Name = cheapest.Name,
			Icon = "🧸",
			Price = cheapest.Price,
			Progress = math.min(coins / cheapest.Price, 1),
			Ready = coins >= cheapest.Price,
		})
	end

	--[[
		Ze světů jen ten první zamčený: odemykají se po pořadě, takže
		nabídnout devátý, když hráč nemá druhý, by byl cíl, ke kterému
		se nedá dojít.
	]]
	local worlds = profile.Worlds or {}
	for _, world in Config.Worlds do
		if not worlds[world.Id] then
			consider({
				Kind = "world",
				Id = world.Id,
				Name = world.Name,
				Icon = "🌍",
				Price = world.Price,
				Progress = math.min(coins / math.max(world.Price, 1), 1),
				Ready = coins >= world.Price,
			})
			break
		end
	end

	return best
end

-- Postup ---------------------------------------------------------------------

--[[
	Jak daleko je hráč k další zdi: podíl 0..1, kolik Poweru má a kolik
	potřebuje.

	`power` se dá předat zvlášť, protože Power se replikuje vlastním,
	mnohem častějším remotem než celý profil — HUD tedy zná novější
	číslo, než jaké je v profilu, a kdyby si ho počítal sám, pruh by
	se s velkým číslem nad ním rozcházel.

	Index se ořezává na počet bariér: po dokončení světa je `Barrier`
	o jedna víc, než kolik zdí trať má, a bez ořezu by pruh na okamžik
	ukázal požadavek zdi, která neexistuje.
]]
--[[
	Kolik hráči přibude za jeden pickup — číslo, které mu vyletí u nohou.

	Je to ta samá skladba, jakou počítá server při sbírání, jen bez
	štěstí: o kritickém zásahu rozhoduje serverová kostka a klient ho
	dopředu neví. Všechno ostatní ale ví, takže se to počítá tady,
	jednou, pro obě strany — dokud se to počítalo zvlášť, chyběl
	klientovi násobič řetězu a při rozjetém combu vyletělo "+100",
	zatímco hráči přibylo dvě stě.
]]
function Economy.collectPreview(pickupValue: number, chain: number, golden: boolean): number
	local value = pickupValue * Combo.multiplier(chain)
	if golden then
		value *= Config.Track.GoldenValue
	end
	return math.floor(value)
end

function Economy.barrierProgress(profile: any, power: number?): (number, number, number)
	local current = power or profile.Power
	local needed = Economy.barrierPower(profile, math.min(profile.Barrier, Config.Track.BarrierCount))
	return math.clamp(current / math.max(needed, 1), 0, 1), current, needed
end

return Economy

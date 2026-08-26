--!strict
--[[
	SquishyService — nákup, držení a mačkání squishy hraček.

	Hračka má dvě poloviny a každá dělá něco jiného:

	  * **držení** je pasivní násobič Poweru; kvůli němu si hráč
	    šetří na další,
	  * **mačkání** je aktivní příjem; kvůli němu má co dělat, když
	    zrovna nikam neběží.

	Kupuje se napřímo za mince. Hráč vidí cenu, vidí číslo, a když si
	našetří, dostane přesně to, na co si šetřil. Tohle je schválně:
	losování o to, jestli hračku vůbec dostane, by z obchodu udělalo
	automat a hráč by nevěděl, kdy se mu to vyplatí.

	Náhodná je jen **varianta** — obyčejná, zlatá nebo duhová (viz
	`Live.Variants`). Nikdy to nejde dolů a nikdy to nesebere to, za co
	hráč zaplatil: koupené číslo je spodní hranice, varianta je bonus
	navrch. Losuje se jednou, při prvním získání; kdo chce lepší šanci,
	zvedne si Luck **předtím**, než si koupí další. Druhý nákup té samé
	hračky proto nic nepřelosuje — z toho by byl přesně ten automat.

	Mačkání běží přes nespolehlivý kanál a je omezené rychlostí. Bez
	stropu by z toho makro udělalo nekonečný zdroj Poweru; se stropem
	je to odměna za pozornost, ne za software.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Economy = require(Shared.Economy)
local Live = require(Shared.Live)
local Perks = require(Shared.Perks)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local Guard = require(script.Parent.GuardService)
local GameService = require(script.Parent.GameService)

local SquishyService = {}

--[[
	Vlastní generátor, ne `math.random`. Ten je sdílený s celým skriptem
	a kdokoliv, kdo si ho jinde znovu nastaví přes `randomseed`, by
	losování variant posunul s sebou.
]]
local rng = Random.new()

type Result = { Ok: boolean, Message: string? }

local function fail(message: string): Result
	return { Ok = false, Message = message }
end

local function succeed(message: string?): Result
	return { Ok = true, Message = message }
end

--[[
	Kolik hraček unese naráz. První je v ruce, zbytek visí na pásku.
]]
function SquishyService.slots(profile: any): number
	local base = if profile.Passes and profile.Passes.Vip
		then Live.MaxHeldVip
		else Live.MaxHeld

	-- Perk "Pack Leader" se přičítá i k VIP: kdo si ho koupil, má ho mít.
	return base + Perks.value(profile, "Slot")
end

--[[
	Přidá hračku do sbírky. Používá se pro odměny (sedmý den, kód,
	dokončený svět) i pro nákup, aby existovalo jedno místo, kde se
	vlastnictví mění.

	Když má hráč volnou ruku, hračka se mu do ní rovnou vloží — jinak
	by si nové odměny musel ručně nasazovat a většina lidí to neudělá.
]]
function SquishyService.grant(player: Player, id: string): boolean
	local profile = DataService.get(player)
	local squishy = Live.squishy(id)
	if not profile or not squishy then
		return false
	end

	--[[
		Varianta se losuje jen u nové hračky. Druhý kus té samé nic
		nepřelosuje — jinak by se dalo kupovat dokola a čekat na duhovou,
		což je automat, ne obchod.
	]]
	profile.Variants = profile.Variants or {}
	local isNew = (profile.Squishies[id] or 0) <= 0
	if isNew then
		profile.Variants[id] = Live.rollVariant(Economy.luckChance(profile), rng:NextNumber())
	end

	profile.Squishies[id] = (profile.Squishies[id] or 0) + 1

	if #profile.Held < SquishyService.slots(profile) and not table.find(profile.Held, id) then
		table.insert(profile.Held, id)
	end

	DataService.markDirty(player)
	return true
end

--[[
	Nákup za mince.

	Duplikát koupit nejde. Kdo hračku má, nemá důvod platit znovu — a
	kdyby to šlo, vypadalo by to jako nastražená past na nepozorné.
]]
function SquishyService.buy(player: Player, id: string): Result
	local profile = DataService.get(player)
	if not profile or typeof(id) ~= "string" then
		return fail("Profile not ready.")
	end

	local squishy = Live.squishy(id)
	if not squishy then
		return fail("Unknown squishy.")
	end
	if squishy.Price <= 0 then
		return fail("That one can't be bought.")
	end
	if (profile.Squishies[id] or 0) > 0 then
		return fail("You already own it.")
	end
	if profile.Coins < squishy.Price then
		return fail("Not enough coins.")
	end

	profile.Coins -= squishy.Price
	profile.Spent += squishy.Price
	SquishyService.grant(player, id)

	require(script.Parent.RetentionService).progress(player, "spend", squishy.Price)

	local Analytics = require(script.Parent.AnalyticsService)
	Analytics.economy(player, "Sink", "Coins", squishy.Price, profile.Coins, "squishy", id)

	require(script.Parent.MilestoneService).squishy(player, squishy)

	GameService.pushProfile(player)

	--[[
		Vzácná varianta se musí říct nahlas. Kdyby se lišila jen barvou
		v panelu, půlka hráčů by nikdy nezjistila, že varianty existují —
		a mechanika, o které nikdo neví, nedělá nic.
	]]
	local variant = Live.variantOf(profile, id)
	if variant > 1 then
		return succeed(`{Live.variantName(variant, squishy.Name)}!`)
	end

	return succeed()
end

--[[
	Vzít do ruky nebo odložit. Jedno tlačítko na obojí: dvě samostatná
	by v seznamu zabrala místo a hráč stejně vždycky chce ten druhý stav.
]]
function SquishyService.hold(player: Player, id: string): Result
	local profile = DataService.get(player)
	if not profile or typeof(id) ~= "string" then
		return fail("Profile not ready.")
	end

	if (profile.Squishies[id] or 0) <= 0 then
		return fail("You don't own it.")
	end

	for index, current in profile.Held do
		if current == id then
			table.remove(profile.Held, index)
			DataService.markDirty(player)
			GameService.pushProfile(player)
			return succeed()
		end
	end

	if #profile.Held >= SquishyService.slots(profile) then
		return fail("Hands full.")
	end

	table.insert(profile.Held, id)
	DataService.markDirty(player)
	GameService.pushProfile(player)

	return succeed()
end

--[[
	Zmáčknutí.

	Hodnotu počítá server ze svého profilu — klient posílá jen to, že
	se zmáčklo. Kdyby posílal i kolik, byl by to nejlevnější exploit
	ve hře.

	Rychlost hlídá `GuardService`; sem se dostane jen to, co projde.
	Vlastní strop `Live.SqueezeRate` je tu podruhé schválně: guard
	chrání server před zahlcením, tohle chrání ekonomiku.
]]
local lastSqueeze: { [Player]: number } = {}

function SquishyService.squeeze(player: Player)
	local profile = DataService.get(player)
	if not profile or #profile.Held == 0 then
		return
	end

	local now = os.clock()
	local minimum = 1 / Live.SqueezeRate
	if now - (lastSqueeze[player] or 0) < minimum then
		return
	end
	lastSqueeze[player] = now

	local value = Economy.squeezeValue(profile, os.time())
	if value <= 0 then
		return
	end

	profile.Power += value
	profile.Squeezes += 1
	DataService.markDirty(player)

	require(script.Parent.RetentionService).progress(player, "squeeze", 1)

	--[[
		Stejný tvar payloadu jako u sbírání. Kdyby se lišil, musel by ho
		klient rozlišovat na dvou místech a jedno z nich by se dřív nebo
		později zapomnělo.
	]]
	--[[
		Zmáčknutí drží combo naživu, ale nestaví ho. Bez toho řetěz
		spadne pokaždé, když hráč na chvíli přestane sbírat — a to je
		přesně chvíle, kdy má hračku v ruce k čemu použít.
	]]
	local chain = GameService.holdCombo(player)

	--[[
		Klíč se jmenuje `Combo`, ne `Chain`: klient čte ten samý payload
		jako u sbírání a jiné jméno by tiše propadlo — lišta comba by
		dál ubývala, i když řetěz už drží.
	]]
	Remotes.PowerChanged:FireClient(player, {
		Power = profile.Power,
		Gained = value,
		Source = "squeeze",
		Combo = chain,
		Window = Economy.comboWindow(profile),
	})
end

--[[
	Co klient potřebuje k vykreslení panelu. Posílá se celý seznam
	i s tím, co hráč nevlastní — zamčená hračka s cenou je důvod hrát
	dál, kdežto prázdný seznam nic neslibuje.
]]
--[[
	Vyzvednutí milníku sbírky.

	Odměna se nepřipisuje sama, i když na ni hráč splnil. Milník, který
	spadne do peněženky bez kliknutí, se ztratí mezi ostatními čísly —
	a smysl sbírky je právě ten okamžik, kdy si ji hráč vezme.
]]
function SquishyService.claimCollection(player: Player, id: string): Result
	local profile = DataService.get(player)
	if not profile or typeof(id) ~= "string" then
		return fail("Profile not ready.")
	end

	local allowed, reason = Economy.canClaimCollection(profile, id)
	if not allowed then
		return fail(reason or "Not there yet.")
	end

	local entry = Live.collectionEntry(id)
	profile.Collection = profile.Collection or {}
	profile.Collection[id] = true
	profile.Gems += entry.Gems

	DataService.markDirty(player)

	local Analytics = require(script.Parent.AnalyticsService)
	Analytics.economy(player, "Source", "Gems", entry.Gems, profile.Gems, "collection", id)

	GameService.pushProfile(player)

	if entry.Bonus > 0 then
		return succeed(`{entry.Text} — +{math.floor(entry.Bonus * 100)}% squishy power forever!`)
	end
	return succeed(`{entry.Text} — +{entry.Gems} 💎`)
end

function SquishyService.snapshot(profile: any)
	local list = {}

	for _, squishy in Live.Squishies do
		local count = profile.Squishies[squishy.Id] or 0
		table.insert(list, {
			Id = squishy.Id,
			Name = squishy.Name,
			Grade = squishy.Grade,
			Price = squishy.Price,
			Power = squishy.Power,
			Squeeze = squishy.Squeeze,
			Shape = squishy.Shape,
			Color = squishy.Color,
			Count = count,
			Variant = Live.variantOf(profile, squishy.Id),
			Held = table.find(profile.Held, squishy.Id) ~= nil,
		})
	end

	return list
end

-- Násobič od hraček v ruce; UI ho ukazuje vedle ostatních zdrojů
function SquishyService.multiplier(profile: any): number
	return Economy.squishMultiplier(profile)
end

function SquishyService.start()
	Guard.wrapFunction("BuySquishy", "Write", SquishyService.buy)
	Guard.wrapFunction("HoldSquishy", "Cheap", SquishyService.hold)
	Guard.wrapFunction("ClaimCollection", "Write", SquishyService.claimCollection)
	Guard.wrapEvent("Squeeze", "Burst", SquishyService.squeeze)

	Players.PlayerRemoving:Connect(function(player)
		lastSqueeze[player] = nil
	end)
end

return SquishyService

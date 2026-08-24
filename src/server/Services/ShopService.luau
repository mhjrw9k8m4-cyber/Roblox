--!strict
--[[
	ShopService — všechno, co se dá koupit: vylepšení, světy, boosty,
	tituly, rebirth a truhla zdarma.

	Každá funkce vrací `{ Ok, Message }`, takže klient nemusí nic domýšlet
	a rovnou zobrazí důvod odmítnutí. Veškerá kontrola ceny a podmínek je
	tady — klient je jen displej.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Live = require(Shared.Live)
local Perks = require(Shared.Perks)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local Guard = require(script.Parent.GuardService)
local GameService = require(script.Parent.GameService)

local ShopService = {}

type Result = { Ok: boolean, Message: string? }

local function fail(message: string): Result
	return { Ok = false, Message = message }
end

local function ok(message: string?): Result
	return { Ok = true, Message = message }
end

-- `sound` je jméno receptu v Assets; klient si ho přehraje sám
local function notify(player: Player, text: string, kind: string, sound: string?)
	Remotes.Notify:FireClient(player, { Text = text, Kind = kind, Sound = sound })
end

-- Vylepšení ------------------------------------------------------------------

function ShopService.buyUpgrade(player: Player, id: string): Result
	local profile = DataService.get(player)
	if not profile or typeof(id) ~= "string" then
		return fail("Profile not ready.")
	end

	local allowed, reason = Economy.canBuyUpgrade(profile, id)
	if not allowed then
		return fail(reason or "Cannot buy.")
	end

	local level = profile.Upgrades[id] or 0
	local price = Config.upgradePrice(id, level) :: number

	profile.Coins -= price
	profile.Upgrades[id] = level + 1
	profile.Spent += price
	DataService.markDirty(player)

	local RetentionService = require(script.Parent.RetentionService)
	RetentionService.progress(player, "upgrade", 1)
	RetentionService.progress(player, "spend", price)

	local Analytics = require(script.Parent.AnalyticsService)
	Analytics.onboarding(player, "FirstUpgrade")
	Analytics.economy(player, "Sink", "Coins", price, profile.Coins, "upgrade", id)

	-- Rychlost se projeví na postavě okamžitě
	if id == "Speed" then
		GameService.applyCharacter(player)
	end

	GameService.pushProfile(player)
	return ok()
end

-- Světy ----------------------------------------------------------------------

function ShopService.buyWorld(player: Player, id: string): Result
	local profile = DataService.get(player)
	if not profile or typeof(id) ~= "string" then
		return fail("Profile not ready.")
	end

	local allowed, reason = Economy.canBuyWorld(profile, id)
	if not allowed then
		return fail(reason or "Cannot buy.")
	end

	local world = Config.world(id)
	profile.Coins -= world.Price
	profile.Worlds[id] = true
	profile.Spent += world.Price
	DataService.markDirty(player)

	require(script.Parent.RetentionService).progress(player, "spend", world.Price)

	local Analytics = require(script.Parent.AnalyticsService)
	local index = Config.worldIndex(id)
	Analytics.economy(player, "Sink", "Coins", world.Price, profile.Coins, "world", id)
	Analytics.world(player, index, false)
	if index == 2 then
		Analytics.onboarding(player, "SecondWorld")
	end

	--[[
		Odemčení světa hlásí obřad, ne toast. Dvě hlášky o téže věci naráz
		si hráč přečte jednu a druhou přehlédne, a to je vždycky ta hezčí.
	]]
	require(script.Parent.MilestoneService).world(player, world, index)
	GameService.enterWorld(player, Config.worldIndex(id))

	return ok()
end

-- Boosty za gemy --------------------------------------------------------------

function ShopService.buyBoost(player: Player, id: string): Result
	local profile = DataService.get(player)
	if not profile or typeof(id) ~= "string" then
		return fail("Profile not ready.")
	end

	local now = os.time()

	local allowed, reason = Economy.canBuyBoost(profile, id, now)
	if not allowed then
		return fail(reason or "Cannot buy.")
	end

	local boost = Config.boost(id)

	-- Cenu bere server ze svého času, ne z toho, co poslal klient —
	-- jinak by si šlo "vybrat" den, kdy je boost v akci.
	profile.Gems -= Economy.boostPrice(id, now)
	-- Koupě za běhu boost prodlouží, nezahodí zbytek
	local current = math.max(profile.Boosts[id] or 0, now)
	profile.Boosts[id] = current + boost.Duration
	DataService.markDirty(player)

	GameService.pushProfile(player)
	notify(player, `{boost.Name} active for {Format.time(profile.Boosts[id] - now)}`, "success")

	return ok()
end

-- Tituly -----------------------------------------------------------------------

function ShopService.equipTitle(player: Player, id: string): Result
	local profile = DataService.get(player)
	if not profile or typeof(id) ~= "string" then
		return fail("Profile not ready.")
	end

	local title
	for _, entry in Config.Titles do
		if entry.Id == id then
			title = entry
			break
		end
	end

	if not title then
		return fail("Unknown title.")
	end
	if profile.Smashes < title.Smashes then
		return fail(`Needs {Format.short(title.Smashes)} smashes.`)
	end

	profile.Title = id
	DataService.markDirty(player)
	GameService.pushProfile(player)

	return ok()
end

-- Truhla zdarma ------------------------------------------------------------------

--[[
	Truhla dá tolik peněz, kolik by hráč vydělal za `FreeChestSeconds`
	hraní. Díky tomu je pořád zajímavá i v pozdní hře, ale nikdy grind
	nepřeskočí.
]]
function ShopService.claimChest(player: Player): Result
	local profile = DataService.get(player)
	if not profile then
		return fail("Profile not ready.")
	end

	local now = os.time()
	local ready, remaining = Economy.canClaimChest(profile, now)
	if not ready then
		return fail(`Ready in {Format.time(remaining)}.`)
	end

	local reward = math.max(
		math.floor(Economy.coinsPerSecond(profile, now) * Config.Rewards.FreeChestSeconds),
		50
	)

	profile.Coins += reward
	profile.NextChestAt = now + Config.Rewards.FreeChestCooldown
	DataService.markDirty(player)

	GameService.pushProfile(player)
	notify(player, `Free chest: +{Format.short(reward)} 💰`, "success")

	return ok()
end

-- Rebirth --------------------------------------------------------------------------

function ShopService.rebirth(player: Player): Result
	local profile = DataService.get(player)
	if not profile then
		return fail("Profile not ready.")
	end

	local allowed, reason = Economy.canRebirth(profile)
	if not allowed then
		return fail(reason or "Cannot rebirth yet.")
	end

	profile.Rebirths += 1
	profile.Gems += Config.Rebirth.GemsPerRebirth

	-- Reset toho, co se dá vygrindovat znovu. Tituly a gemy zůstávají,
	-- protože ty jsou odměna za odehraný čas, ne za aktuální běh.
	profile.Coins = 0
	profile.Power = 0
	profile.Barrier = 1
	--[[
		Perk "Muscle Memory" nechá část úrovní. Zaokrouhluje se dolů, takže
		na první úrovni perku si hráč z deseti úrovní odnese jednu — ne
		"skoro jednu", což by v UI vypadalo jako podvod.
	]]
	local keep = Perks.value(profile, "Keep")
	if keep > 0 then
		local kept = {}
		for id, level in profile.Upgrades do
			local left = math.floor(level * keep)
			if left > 0 then
				kept[id] = left
			end
		end
		profile.Upgrades = kept
	else
		profile.Upgrades = {}
	end
	profile.Worlds = { [Config.Worlds[1].Id] = true }
	profile.WorldIndex = 1
	-- Kola se musí nulovat spolu se světy. Jinak by hráč po rebirthu stál
	-- s vynulovanou ekonomikou před zdmi z dvacátého kola.
	profile.Laps = {}

	DataService.markDirty(player)
	DataService.save(player)

	GameService.enterWorld(player, 1)
	GameService.applyCharacter(player)

	-- Rebirth mění obojí naráz: přibude rebirthů, ale ubudou světy.
	-- Kus vázaný na počet světů by tak zůstal nasazený neprávem.
	require(script.Parent.CosmeticService).apply(player)

	require(script.Parent.AnalyticsService).custom(player, "rebirth", profile.Rebirths)
	require(script.Parent.MilestoneService).rebirth(player, profile.Rebirths)

	local bonus = math.floor(Config.Rebirth.BonusPerRebirth * 100)
	notify(
		player,
		`REBIRTH #{profile.Rebirths}! +{bonus}% power & coins forever, +{Config.Rebirth.GemsPerRebirth} 💎`,
		"success",
		"Rebirth"
	)

	return ok()
end

-- Napojení remote funkcí ---------------------------------------------------------------

--[[
	Nákup perku za tokeny z rebirthu.

	Tokeny se nikde neukládají — dostupné = rebirthy mínus to, co už je
	v koupených úrovních (viz Perks.spent). Nejde tak vyrobit stav, ve
	kterém profil tvrdí, že tokeny má, ale nikdy je nezaplatil.
]]
function ShopService.buyPerk(player: Player, id: string)
	local profile = DataService.get(player)
	if not profile or typeof(id) ~= "string" then
		return fail("Profile not ready.")
	end

	local allowed, reason = Perks.canBuy(profile, id)
	if not allowed then
		return fail(reason or "Cannot buy that.")
	end

	Perks.apply(profile, id)
	DataService.markDirty(player)

	-- Které větve si hráči vybírají je to nejužitečnější, co o stromu
	-- jde zjistit: větev, kterou nikdo nebere, je špatně naceněná
	-- nebo špatně vysvětlená.
	require(script.Parent.AnalyticsService).custom(player, "perk", Perks.level(profile, id), {
		Perk = id,
		Rebirths = profile.Rebirths,
	})

	-- Několik větví mění věci, které už na hráči visí
	GameService.applyCharacter(player)
	GameService.pushProfile(player)

	local perk = Perks.get(id)
	notify(player, `{perk and perk.Name or id} → level {Perks.level(profile, id)}`, "success", "Purchase")

	return ok()
end

--[[
	Směna gemů za mince. Kurz je násobek příjmu za sekundu, takže má
	smysl v každé fázi hry — viz Economy.exchangeValue.
]]
function ShopService.exchange(player: Player): Result
	local profile = DataService.get(player)
	if not profile then
		return fail("Profile not ready.")
	end

	local allowed, reason = Economy.canExchange(profile)
	if not allowed then
		return fail(reason or "Cannot exchange.")
	end

	local now = os.time()
	-- Hodnota se počítá PŘED odečtením gemů: gemy do příjmu nevstupují,
	-- ale kdyby to někdo v budoucnu změnil, tenhle pořadí drží kurz.
	local coins = Economy.exchangeValue(profile, now)

	profile.Gems -= Live.Exchange.Gems
	profile.Coins += coins
	DataService.markDirty(player)

	require(script.Parent.AnalyticsService).economy(
		player, "Sink", "Gems", Live.Exchange.Gems, profile.Gems, "exchange"
	)

	GameService.pushProfile(player)
	notify(player, `Traded {Live.Exchange.Gems} 💎 for {Format.short(coins)} 💰`, "success", "Purchase")

	return ok()
end

function ShopService.start()
	Guard.wrapFunction("BuyUpgrade", "Write", ShopService.buyUpgrade)
	Guard.wrapFunction("BuyWorld", "Write", ShopService.buyWorld)
	Guard.wrapFunction("BuyBoost", "Write", ShopService.buyBoost)
	Guard.wrapFunction("EquipTitle", "Cheap", ShopService.equipTitle)
	Guard.wrapFunction("ClaimChest", "Write", ShopService.claimChest)
	Guard.wrapFunction("DoRebirth", "Write", ShopService.rebirth)
	Guard.wrapFunction("BuyPerk", "Write", ShopService.buyPerk)
	Guard.wrapFunction("ExchangeGems", "Write", ShopService.exchange)
end

return ShopService

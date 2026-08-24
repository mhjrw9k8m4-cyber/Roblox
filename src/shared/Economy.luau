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

local function upgradeLevel(profile: any, id: string): number
	return (profile.Upgrades and profile.Upgrades[id]) or 0
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
	Násobič od nasazených petů. Bonusy se sčítají (dva pety po +30 %
	dají +60 %), VIP pak výsledek ještě přenásobí.

	Počítá se tady, ve sdíleném modulu, aby klient v UI ukazoval přesně
	to samé číslo, jaké server použije při výpočtu.
]]
function Economy.petMultiplier(profile: any): number
	local total = 1

	for _, petId in profile.EquippedPets or {} do
		local pet = Live.pet(petId)
		if pet then
			total += pet.Power
		end
	end

	if profile.Passes and profile.Passes.Vip then
		total *= Live.PassBonus.Vip
	end

	return total
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
		* Economy.petMultiplier(profile)
		* Economy.boostMultiplier(profile, "Power", now)

	return math.max(math.floor(total), 1)
end

function Economy.coinMultiplier(profile: any, now: number): number
	return Economy.rebirthMultiplier(profile)
		* Economy.passCoinMultiplier(profile)
		* Economy.boostMultiplier(profile, "Coins", now)
end

function Economy.collectRadius(profile: any): number
	local upgrade = Config.upgrade("Magnet")
	return Config.Track.CollectRadius + upgradeLevel(profile, "Magnet") * upgrade.PerLevel
end

function Economy.walkSpeed(profile: any): number
	local upgrade = Config.upgrade("Speed")
	return 16 + upgradeLevel(profile, "Speed") * upgrade.PerLevel
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
	return Combo.Window + Perks.value(profile, "Combo")
end

-- Gemy za dokončené kolo světa: základ světa plus perk "Prospector".
function Economy.clearGems(profile: any, worldIndex: number): number
	local world = Config.Worlds[worldIndex]
	local base = if world then world.Gems else 1
	return base + Perks.value(profile, "Gem")
end

-- Peníze za proražení bariéry. Gemy se za jednotlivé bariéry nedávají,
-- ty padají až za dokončené kolo (viz GameService.worldCleared).
function Economy.smashReward(profile: any, barrierIndex: number, now: number): number
	local required = Economy.barrierPower(profile, barrierIndex)
	local bonus = Economy.overkill(profile.Power or 0, required, profile)

	return math.floor(Economy.barrierCoins(profile, barrierIndex) * Economy.coinMultiplier(profile, now) * bonus)
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

function Economy.canBuyBoost(profile: any, id: string): (boolean, string?)
	local boost = Config.boost(id)
	if not boost then
		return false, "Unknown boost."
	end
	if profile.Gems < boost.Gems then
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

-- Postup ---------------------------------------------------------------------

-- Kolik procent do další bariéry hráč má (0..1) a kolik Poweru chybí
function Economy.barrierProgress(profile: any): (number, number, number)
	local needed = Economy.barrierPower(profile, math.min(profile.Barrier, Config.Track.BarrierCount))
	local ratio = math.clamp(profile.Power / math.max(needed, 1), 0, 1)
	return ratio, profile.Power, needed
end

-- Kolik pickupů celkem svět nabízí (pro kontrolu, že je Power dosažitelný)
function Economy.worldPickupCount(): number
	return Track.PickupCount
end

return Economy

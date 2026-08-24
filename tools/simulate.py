#!/usr/bin/env python3
"""
Simulace ekonomiky Power Smash.

Spustí skutečné moduly hry (Config + Economy) mimo Roblox a změří, za jak
dlouho hráč projde světy, kolik trvá první rebirth a jestli je vůbec na co
sáhnout. Po každé změně čísel v Configu tímhle ověříš, že se grind nerozpadl.

Použití:
    python3 tools/simulate.py                # 24 h hraní
    python3 tools/simulate.py --hours 6
    python3 tools/simulate.py --rebirth      # smyčka rebirthů

Potřebuje binárku `luau` v PATH nebo vedle skriptu
(https://github.com/luau-lang/luau/releases).
"""

import argparse
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Config používá Color3 a Enum.Material jen jako data, stačí je zastoupit.
STUB = """Color3 = { fromRGB = function() return {} end }
Enum = { Material = setmetatable({}, { __index = function(_, k) return k end }) }

-- Roblox `Random` mimo engine neexistuje; na losování petů stačí
-- jednoduchý generátor s pevným seedem, aby byl běh opakovatelný.
Random = {
	new = function(seed)
		local state = (seed or 1) % 2147483647
		local generator = {}

		function generator:NextNumber(min, max)
			state = (state * 1103515245 + 12345) % 2147483648
			local value = state / 2147483648
			if min then
				return min + value * ((max or 1) - min)
			end
			return value
		end

		function generator:NextInteger(min, max)
			return math.floor(generator:NextNumber(min, max + 1))
		end

		return generator
	end,
}
"""

PLAYER = r"""
local BARRIERS = Config.Track.BarrierCount

local function newPlayer()
	return {
		Coins = 0, Gems = 5, Power = 0, WorldIndex = 1, Barrier = 1,
		Worlds = { [Config.Worlds[1].Id] = true },
		Upgrades = {}, Boosts = {}, Rebirths = 0, Smashes = 0,
		Pets = {}, EquippedPets = {}, Passes = {}, Laps = {}, Perks = {},
	}
end

--[[
	Pety kupuje i simulovaný hráč — jinak by měření tempa ignorovalo
	systém, který násobí Power nejvíc ze všech. Losuje se skutečnými
	vahami z Live, jen s pevným seedem, aby byl běh opakovatelný.
]]
local petRandom = Random.new(1337)

local function rollPet(eggId)
	local pool = Live.eggPool(eggId)
	local total = 0
	for _, pet in pool do
		total += Live.rarity(pet.Rarity).Weight
	end

	local roll = petRandom:NextNumber(0, total)
	local running = 0
	for _, pet in pool do
		running += Live.rarity(pet.Rarity).Weight
		if roll <= running then
			return pet
		end
	end
	return pool[#pool]
end

-- Nasadí tři nejsilnější vlastněné pety
local function reequip(p)
	local owned = {}
	for petId, count in p.Pets do
		if count > 0 then
			local pet = Live.pet(petId)
			if pet then
				table.insert(owned, pet)
			end
		end
	end

	table.sort(owned, function(a, b)
		return a.Power > b.Power
	end)

	p.EquippedPets = {}
	for index = 1, math.min(Live.MaxEquippedPets, #owned) do
		table.insert(p.EquippedPets, owned[index].Id)
	end
end

-- Průměrná síla petu z daného vejce (vážený průměr podle vzácností)
local function expectedPower(eggId)
	local pool = Live.eggPool(eggId)
	local total, sum = 0, 0
	for _, pet in pool do
		local weight = Live.rarity(pet.Rarity).Weight
		total += weight
		sum += weight * pet.Power
	end
	return if total > 0 then sum / total else 0
end

-- Nejslabší z nasazených; dokud jich nemá plný počet, je to nula
local function weakestEquipped(p)
	if #p.EquippedPets < Live.MaxEquippedPets then
		return 0
	end

	local worst = math.huge
	for _, petId in p.EquippedPets do
		local pet = Live.pet(petId)
		if pet and pet.Power < worst then
			worst = pet.Power
		end
	end
	return worst
end

--[[
	Nákup vajec tak, jak to dělá skutečný hráč: kupuje jen dokud mu vejce
	může přinést zlepšení, a nikdy za ně nedá víc než desetinu jmění.

	První verze simulace kupovala pořád a při každé příležitosti — hráč
	se pak nikdy nedostal ze druhého světa, protože všechny peníze mizely
	v nejlevnějším vejci. To není chyba hry, ale chyba modelu chování.
]]
local function buyEggs(p)
	local bought = true
	while bought do
		bought = false
		local floor = weakestEquipped(p)

		local best
		for _, egg in Live.Eggs do
			local worthIt = expectedPower(egg.Id) > floor
			local affordable = p.Coins >= egg.Price * 10
			if worthIt and affordable and (not best or egg.Price > best.Price) then
				best = egg
			end
		end

		if best then
			p.Coins -= best.Price
			local pet = rollPet(best.Id)
			if pet then
				p.Pets[pet.Id] = (p.Pets[pet.Id] or 0) + 1
				reequip(p)
			end
			bought = true
		end
	end
end

--[[
	Kolik pickupů hráč posbírá za sekundu. Není to volný parametr:
	běží rychlostí danou upgradem Speed a sbírá vše, na co dosáhne
	magnetem, takže obojí se do tempa promítne.
]]
local function pickupsPerSecond(p)
	local speed = Economy.walkSpeed(p)
	local radius = Economy.collectRadius(p)
	local lanes = #Config.Track.Lanes
	local rowSpacing = Config.Track.SegmentLength / #Config.Track.RowOffsets

	-- kolik sloupců magnet pokryje naráz
	local covered = math.min(math.max(radius / 13, 1), lanes)
	-- kolik řad za sekundu hráč mine
	local rows = speed / rowSpacing
	local manual = rows * covered

	-- vyšší Luck zvedá průměrnou hodnotu, ne počet
	return manual + Economy.autoRate(p, 0)
end

--[[
	Průměrný násobič z comba.

	Nepočítá se se stropem: hráč běží tratí, mezi segmenty a u bariéry
	řetěz občas spadne. Podíl `ComboUptime` říká, jakou část stropu
	vydrží držet — schválně konzervativně, aby simulace radši
	podstřelila, než aby slibovala časy, které nikdo nezahraje.
]]
local COMBO_UPTIME = 0.55

local function comboMultiplier()
	return 1 + (Combo.maxMultiplier() - 1) * COMBO_UPTIME
end

local function averagePickup(p)
	local luck = Economy.luckChance(p)
	return Economy.pickupValue(p, 0) * (1 + luck * 4) * comboMultiplier()
end

--[[
	Projde jednu bariéru: nasbírá potřebný Power a prorazí. Vrací sekundy.

	Spodní hranice není kosmetika — i s nekonečným Powerem musí hráč
	k další bariéře fyzicky doběhnout, což je celá délka segmentu.
	Bez toho by simulace (a odhad příjmu) tvrdila nesmysly.
]]
local function clearBarrier(p)
	local needed = Economy.barrierPower(p, p.Barrier)
	local missing = math.max(needed - p.Power, 0)
	local rate = averagePickup(p) * pickupsPerSecond(p)
	local travel = Config.Track.SegmentLength / Economy.walkSpeed(p)
	local collect = missing / math.max(rate, 0.001)
	local seconds = math.max(collect, travel)

	--[[
		Když je bariéra vázaná na běh, hráč u ní stojí s víc Powerem, než
		potřeboval — sbíral celou cestu. Ten přebytek se počítá do výplaty
		(overkill), takže ho simulace musí opravdu držet, ne zahodit.
	]]
	p.Power = p.Power + rate * seconds

	-- Diagnostika: kolik bariér je vázaných na běh, ne na sbírání
	BOUND_TOTAL = (BOUND_TOTAL or 0) + 1
	if travel > collect then
		BOUND_TRAVEL = (BOUND_TRAVEL or 0) + 1
	end

	OVER_SUM = (OVER_SUM or 0) + Economy.overkill(p.Power, needed)

	local coins = Economy.smashReward(p, p.Barrier, 0)
	p.Power = 0
	p.Coins += coins
	p.Gems += Config.Worlds[p.WorldIndex].Gems
	p.Smashes += 1
	p.Barrier += 1

	if p.Barrier > BARRIERS then
		local total = 0
		for index = 1, BARRIERS do
			total += Economy.barrierCoins(p, index)
		end
		p.Coins += math.floor(total * 2 * Economy.coinMultiplier(p, 0))
		p.Gems += Config.Worlds[p.WorldIndex].Gems * 5
		p.Barrier = 1
		p.Power = 0

		-- Další kolo téhož světa: zdi i výplata povyskočí (viz Config.Track.LapPower)
		local id = Config.Worlds[p.WorldIndex].Id
		p.Laps[id] = (p.Laps[id] or 0) + 1
	end

	return seconds
end

-- Kupuje nejlevnější dostupné vylepšení, dokud mu zbývá rezerva
local function shop(p)
	buyEggs(p)

	local bought = true
	while bought do
		bought = false
		local bestId, bestPrice
		for _, u in Config.Upgrades do
			local price = Config.upgradePrice(u.Id, p.Upgrades[u.Id] or 0)
			if price and price <= p.Coins * 0.5 and (not bestPrice or price < bestPrice) then
				bestId, bestPrice = u.Id, price
			end
		end
		if bestId then
			p.Coins -= bestPrice
			p.Upgrades[bestId] = (p.Upgrades[bestId] or 0) + 1
			bought = true
		end
	end
end

-- Odemkne další svět, jakmile na něj má, a hned do něj přejde
local function unlock(p, log, t)
	for index, world in Config.Worlds do
		if Economy.canBuyWorld(p, world.Id) then
			p.Coins -= world.Price
			p.Worlds[world.Id] = true
			p.WorldIndex = index
			p.Power = 0
			p.Barrier = 1
			if log then
				log[#log + 1] = string.format("%9.1f min   %s", t / 60, world.Name)
			end
		end
	end
end
"""

MODE_WORLDS = r"""
local p, t, log = newPlayer(), 0, {}

while t < LIMIT do
	t += clearBarrier(p)
	shop(p)
	unlock(p, log, t)
end

print("=== Odemykani svetu ===")
for _, line in ipairs(log) do
	print("  " .. line)
end
print("")
print(string.format("  Po %.0f h: svet %d, %d prurazu, prijem %.4g /s",
	LIMIT / 3600, p.WorldIndex, p.Smashes, Economy.coinsPerSecond(p, 0)))

-- Strojově čitelný souhrn pro CI: kolik světů se za běh odemklo
local unlocked = 0
for _, world in Config.Worlds do
	if p.Worlds[world.Id] then
		unlocked += 1
	end
end
print(string.format("UNLOCKED=%d", unlocked))
print(string.format("BEH=%d%% (%d z %d barier)",
	math.floor((BOUND_TRAVEL or 0) / math.max(BOUND_TOTAL or 1, 1) * 100),
	BOUND_TRAVEL or 0, BOUND_TOTAL or 0))
print(string.format("OVERKILL=%.1fx prumerne", (OVER_SUM or 0) / math.max(BOUND_TOTAL or 1, 1)))
"""

MODE_REBIRTH = r"""
local p, t, count = newPlayer(), 0, 0

print("=== Smycka rebirthu ===")
while t < LIMIT do
	t += clearBarrier(p)
	shop(p)
	unlock(p, nil, t)

	if Economy.canRebirth(p) then
		count += 1
		print(string.format("  rebirth #%d v %6.0f min (%.1f h) -> nasobic %.2fx",
			p.Rebirths + 1, t / 60, t / 3600,
			1 + (p.Rebirths + 1) * Config.Rebirth.BonusPerRebirth))
		p.Rebirths += 1
		p.Coins = 0
		p.Power = 0
		p.Barrier = 1
		p.Upgrades = {}
		p.Worlds = { [Config.Worlds[1].Id] = true }
		p.WorldIndex = 1
		p.Laps = {}
	end
end

if count == 0 then
	print("  Zadny rebirth nedosazen -- BaseCost je nejspis moc vysoky.")
end
"""


def module_body(relative: str) -> str:
    """Tělo modulu bez `require` řádků — závislosti dodáme jako lokální proměnné."""
    source = (ROOT / relative).read_text(encoding="utf-8")
    return re.sub(r"^local \w+ = require\(.*\)\n", "", source, flags=re.M)


def find_luau() -> str:
    local = pathlib.Path(__file__).parent / "luau"
    if local.is_file():
        return str(local)
    found = shutil.which("luau")
    if found:
        return found
    sys.exit(
        "Nenašel jsem binárku `luau`.\n"
        "Stáhni ji z https://github.com/luau-lang/luau/releases a dej do PATH nebo do tools/."
    )


def build_script(hours: float, rebirth: bool) -> str:
    return "\n".join([
        STUB,
        f"local LIMIT = {hours * 3600}",
        "local Config = (function()", module_body("src/shared/Config.luau"), "end)()",
        "local Live = (function()", module_body("src/shared/Live.luau"), "end)()",
        "local Track = (function()", module_body("src/shared/Track.luau"), "end)()",
        "local Combo = (function()", module_body("src/shared/Combo.luau"), "end)()",
        "local Perks = (function()", module_body("src/shared/Perks.luau"), "end)()",
        "local Economy = (function()", module_body("src/shared/Economy.luau"), "end)()",
        PLAYER,
        MODE_REBIRTH if rebirth else MODE_WORLDS,
    ])


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--hours", type=float, default=24, help="kolik hodin hraní simulovat")
    parser.add_argument("--rebirth", action="store_true", help="ukázat smyčku rebirthů")
    parser.add_argument(
        "--min-worlds",
        type=int,
        default=0,
        help="selhat, pokud se za daný čas neodemkne aspoň tolik světů (pro CI)",
    )
    args = parser.parse_args()

    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as handle:
        handle.write(build_script(args.hours, args.rebirth))
        path = handle.name

    try:
        result = subprocess.run([find_luau(), path], capture_output=True, text=True, timeout=600)
        sys.stdout.write(result.stdout)
        if result.returncode != 0:
            sys.stderr.write(result.stderr)
            sys.exit(result.returncode)

        # Kontrola pro CI. Bez ní by změna čísel, která se zkompiluje,
        # ale udělá svět nedosažitelným, prošla bez povšimnutí.
        if args.min_worlds > 0:
            match = re.search(r"^UNLOCKED=(\d+)$", result.stdout, re.M)
            unlocked = int(match.group(1)) if match else 0
            if unlocked < args.min_worlds:
                sys.stderr.write(
                    f"\nCHYBA: za {args.hours} h se odemklo {unlocked} světů, "
                    f"očekáváno aspoň {args.min_worlds}.\n"
                )
                sys.exit(1)
            print(f"\nOK: odemčeno {unlocked} světů (minimum {args.min_worlds}).")
    finally:
        pathlib.Path(path).unlink(missing_ok=True)


if __name__ == "__main__":
    main()

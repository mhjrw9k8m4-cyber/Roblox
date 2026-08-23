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
"""

PLAYER = r"""
local BARRIERS = Config.Track.BarrierCount

local function newPlayer()
	return {
		Coins = 0, Gems = 5, Power = 0, WorldIndex = 1, Barrier = 1,
		Worlds = { [Config.Worlds[1].Id] = true },
		Upgrades = {}, Boosts = {}, Rebirths = 0, Smashes = 0,
	}
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

local function averagePickup(p)
	local luck = Economy.luckChance(p)
	return Economy.pickupValue(p, 0) * (1 + luck * 4)
end

--[[
	Projde jednu bariéru: nasbírá potřebný Power a prorazí. Vrací sekundy.

	Spodní hranice není kosmetika — i s nekonečným Powerem musí hráč
	k další bariéře fyzicky doběhnout, což je celá délka segmentu.
	Bez toho by simulace (a odhad příjmu) tvrdila nesmysly.
]]
local function clearBarrier(p)
	local needed = Config.barrierPower(p.WorldIndex, p.Barrier)
	local missing = math.max(needed - p.Power, 0)
	local rate = averagePickup(p) * pickupsPerSecond(p)
	local travel = Config.Track.SegmentLength / Economy.walkSpeed(p)
	local seconds = math.max(missing / math.max(rate, 0.001), travel)

	p.Power = needed
	local coins = math.floor(Config.barrierCoins(p.WorldIndex, p.Barrier) * Economy.coinMultiplier(p, 0))
	p.Coins += coins
	p.Gems += Config.Worlds[p.WorldIndex].Gems
	p.Smashes += 1
	p.Barrier += 1

	if p.Barrier > BARRIERS then
		local total = 0
		for index = 1, BARRIERS do
			total += Config.barrierCoins(p.WorldIndex, index)
		end
		p.Coins += math.floor(total * 2 * Economy.coinMultiplier(p, 0))
		p.Gems += Config.Worlds[p.WorldIndex].Gems * 5
		p.Barrier = 1
		p.Power = 0
	end

	return seconds
end

-- Kupuje nejlevnější dostupné vylepšení, dokud mu zbývá rezerva
local function shop(p)
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
        "local Track = (function()", module_body("src/shared/Track.luau"), "end)()",
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
    finally:
        pathlib.Path(path).unlink(missing_ok=True)


if __name__ == "__main__":
    main()

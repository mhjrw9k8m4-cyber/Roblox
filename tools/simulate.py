#!/usr/bin/env python3
"""
Simulace ekonomiky ASMR Studia.

Spustí skutečné moduly hry (Config + Economy) mimo Roblox a změří,
za jak dlouho si hráč na co vydělá. Po každé změně cen v Configu
tímhle ověříš, že se grind nerozpadl.

Použití:
    python3 tools/simulate.py                # 24 h hraní
    python3 tools/simulate.py --hours 12     # kratší běh
    python3 tools/simulate.py --rebirth      # smyčka rebirthů

Potřebuje binárku `luau` v PATH nebo vedle skriptu.
Stáhneš ji z https://github.com/luau-lang/luau/releases (luau-ubuntu.zip).
"""

import argparse
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Náhrady Roblox API — Config používá Color3 a Enum.Material jen jako data,
# takže stačí, aby existovaly.
STUB = """Color3 = { fromRGB = function() return {} end }
Enum = { Material = setmetatable({}, { __index = function(_, k) return k end }) }
"""

PLAYER = r"""
local function newPlayer()
	return {
		Coins = 0, Xp = 0, Level = 1, Rebirths = 0,
		EquippedTool = Config.Tools[1].Id, EquippedObject = Config.Objects[1].Id,
		Tools = { [Config.Tools[1].Id] = true },
		Objects = { [Config.Objects[1].Id] = true },
		Upgrades = {},
	}
end

-- Jeden materiál od začátku do rozbití; vrátí, kolik to trvalo sekund.
local function grindOne(p)
	local obj = Config.object(p.EquippedObject)
	local dmg, cd = Economy.damage(p), Economy.cooldown(p)
	local hits = math.max(math.ceil(obj.Integrity / dmg), 1)
	-- combo roste v průběhu kusu, průměr bereme konzervativně
	local avgCombo = math.min(1 + (hits / 2) * Config.Core.ComboStep, Economy.comboMax(p))

	for _ = 1, hits do
		p.Coins += Economy.strikeReward(p, obj.Id, math.min(dmg, obj.Integrity), avgCombo)
	end
	p.Coins += Economy.destroyBonus(p, obj.Id)
	Economy.addXp(p, obj.Xp * 1.5)
	return hits * cd
end

-- Chování hráče: kupuje nejlevnější dostupné vylepšení, dokud mu zbývá
-- rezerva, a odemyká všechno, na co dosáhne.
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

local function unlock(p, log, t)
	for _, e in Config.Tools do
		if Economy.canUnlockTool(p, e.Id) then
			p.Coins -= e.Price
			p.Tools[e.Id] = true
			p.EquippedTool = e.Id
			if log then
				log[#log + 1] = string.format("%9.1f min   lvl %2d   nuz: %s", t / 60, p.Level, e.Name)
			end
		end
	end
	for _, e in Config.Objects do
		if Economy.canUnlockObject(p, e.Id) then
			p.Coins -= e.Price
			p.Objects[e.Id] = true
			if log then
				log[#log + 1] = string.format("%9.1f min   lvl %2d   mat: %s", t / 60, p.Level, e.Name)
			end
		end
	end
	-- vždycky krájí nejhodnotnější odemčený materiál
	local best = Config.Objects[1]
	for _, e in Config.Objects do
		if p.Objects[e.Id] and e.Value > best.Value then
			best = e
		end
	end
	p.EquippedObject = best.Id
end
"""

MODE_UNLOCKS = r"""
local p, t, log = newPlayer(), 0, {}
local maxLevelAt

while t < LIMIT do
	t += grindOne(p)
	if p.Level >= Config.Level.MaxLevel and not maxLevelAt then
		maxLevelAt = t / 60
	end
	shop(p)
	unlock(p, log, t)
end

print("=== Odemykani ===")
for _, line in ipairs(log) do
	print("  " .. line)
end
print("")
print(string.format("  Max uroven %d dosazena: %s", Config.Level.MaxLevel,
	maxLevelAt and string.format("%.0f min", maxLevelAt) or "NEDOSAZENA"))
print(string.format("  Prijem na konci: %.4g /s", Economy.coinsPerSecond(p)))
"""

MODE_REBIRTH = r"""
local p, t = newPlayer(), 0
local count = 0

print("=== Smycka rebirthu ===")
while t < LIMIT do
	t += grindOne(p)

	if Economy.canRebirth(p) then
		count += 1
		print(string.format("  rebirth #%d v %6.0f min (%.1f h) -> nasobic %.2fx",
			p.Rebirths + 1, t / 60, t / 3600, 1 + (p.Rebirths + 1) * Config.Rebirth.BonusPerRebirth))
		p.Rebirths += 1
		p.Coins = 0
		p.Upgrades = {}
		p.Objects = { [Config.Objects[1].Id] = true }
		p.EquippedObject = Config.Objects[1].Id
		if not Config.Rebirth.KeepTools then
			p.Tools = { [Config.Tools[1].Id] = true }
			p.EquippedTool = Config.Tools[1].Id
		end
	end

	shop(p)
	unlock(p, nil, t)
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
    for candidate in ("luau", str(pathlib.Path(__file__).parent / "luau")):
        found = shutil.which(candidate) or (candidate if pathlib.Path(candidate).is_file() else None)
        if found:
            return found
    sys.exit(
        "Nenašel jsem binárku `luau`.\n"
        "Stáhni ji z https://github.com/luau-lang/luau/releases a dej do PATH."
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--hours", type=float, default=24, help="kolik hodin hraní simulovat (výchozí 24)")
    parser.add_argument("--rebirth", action="store_true", help="místo odemykání ukázat smyčku rebirthů")
    args = parser.parse_args()

    script = "\n".join([
        STUB,
        f"local LIMIT = {args.hours * 3600}",
        "local Config = (function()", module_body("src/shared/Config.luau"), "end)()",
        "local Economy = (function()", module_body("src/shared/Economy.luau"), "end)()",
        PLAYER,
        MODE_REBIRTH if args.rebirth else MODE_UNLOCKS,
    ])

    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as handle:
        handle.write(script)
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

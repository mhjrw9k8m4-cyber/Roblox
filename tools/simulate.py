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

-- Roblox `Random` mimo engine neexistuje; na drobné rozhodování stačí
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
		Squishies = {}, Held = {}, Passes = {}, Laps = {}, Perks = {},
		Clock = 0, Surge = 0,
	}
end

--[[
	Squishy hračky kupuje i simulovaný hráč — jinak by měření tempa
	ignorovalo systém, který násobí Power nejvíc ze všech.

	Kupuje se napřímo, takže tu není co losovat: bere se nejdražší
	hračka, na kterou má desetinásobek ceny. Ten desetinásobek je model
	chování, ne pravidlo hry — první verze simulace kupovala při každé
	příležitosti a hráč se pak nikdy nedostal ze druhého světa, protože
	všechny peníze mizely v hračkách.

	Mačkání se schválně NEmodeluje. Je to ruční činnost a ne každý ji
	bude dělat; simulace tak měří spodní hranici tempa, ne tu nejlepší
	možnou. Kdyby počítala i s mačkáním, slibovala by časy, které
	nikdo nezahraje.
]]
local function reequip(p)
	local owned = {}
	for id, count in p.Squishies do
		if count > 0 then
			local squishy = Live.squishy(id)
			if squishy then
				table.insert(owned, squishy)
			end
		end
	end

	table.sort(owned, function(a, b)
		return a.Power > b.Power
	end)

	p.Held = {}
	for index = 1, math.min(Live.MaxHeld, #owned) do
		table.insert(p.Held, owned[index].Id)
	end
end

-- Nejslabší z držených; dokud jich nemá plný počet, je to nula
local function weakestHeld(p)
	if #p.Held < Live.MaxHeld then
		return 0
	end

	local worst = math.huge
	for _, id in p.Held do
		local squishy = Live.squishy(id)
		if squishy and squishy.Power < worst then
			worst = squishy.Power
		end
	end
	return worst
end

TOY_LOG = {}
CLOCK = 0

local function buySquishies(p)
	local bought = true
	while bought do
		bought = false
		local floor = weakestHeld(p)

		local best
		for _, squishy in Live.forSale() do
			local worthIt = squishy.Power > floor
			local affordable = p.Coins >= squishy.Price * 10
			local owned = (p.Squishies[squishy.Id] or 0) > 0
			if worthIt and affordable and not owned and (not best or squishy.Price > best.Price) then
				best = squishy
			end
		end

		if best then
			p.Coins -= best.Price
			p.Squishies[best.Id] = 1
			reequip(p)
			bought = true
			--[[
				Zapisuje se, KDY na kterou hračku hráč dosáhl. Žebříček
				hraček kopíruje pořadí levelů, takže když se některá
				v běhu vůbec neobjeví, je nejdražší kus ve hře jen
				číslo v tabulce, na které nikdo nedosáhne.
			]]
			TOY_LOG[#TOY_LOG + 1] = string.format("%9.1f min   %s (%.4g)", CLOCK / 60, best.Name, best.Price)
		end
	end
end

--[[
	Kolik pickupů hráč posbírá za sekundu. Není to volný parametr:
	běží rychlostí danou upgradem Speed a sbírá vše, na co dosáhne
	magnetem, takže obojí se do tempa promítne.
]]
--[[
	Nálet po silném průrazu zrychlí běh a zvětší dosah na pár vteřin.
	Trvá zhruba tak dlouho jako přeběh k další zdi, takže se modeluje
	jako "platí pro celou příští bariéru, nebo neplatí vůbec".

	`p.Surge` drží čas vypršení; simulace jede v sekundách od začátku,
	takže se s ním dá pracovat úplně stejně jako na serveru.
]]
local function pickupsPerSecond(p, now)
	local speed = Economy.walkSpeed(p, p.Surge, now)
	local radius = Economy.collectRadius(p, p.Surge, now)
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

--[[
	Zlaté pickupy zvedají PRŮMĚRNOU hodnotu sbírání: malá část jich stojí
	mnohonásobek. Do modelu se tedy nepromítají jako událost, ale jako
	posun průměru — na tempo progrese to vychází stejně a nemusí se
	sledovat, který konkrétní pickup hráč sebral.
]]
local function goldenBonus()
	local share = Config.Track.GoldenPerMille / 1000
	return 1 + share * (Config.Track.GoldenValue - 1)
end

local function averagePickup(p)
	local luck = Economy.luckChance(p)
	return Economy.pickupValue(p, 0) * (1 + luck * 4) * comboMultiplier() * goldenBonus()
end

--[[
	Projde jednu bariéru: nasbírá potřebný Power a prorazí. Vrací sekundy.

	Spodní hranice není kosmetika — i s nekonečným Powerem musí hráč
	k další bariéře fyzicky doběhnout, což je celá délka segmentu.
	Bez toho by simulace (a odhad příjmu) tvrdila nesmysly.
]]
local function clearBarrier(p)
	local now = p.Clock or 0
	local needed = Economy.barrierPower(p, p.Barrier)
	local missing = math.max(needed - p.Power, 0)
	local rate = averagePickup(p) * pickupsPerSecond(p, now)
	local travel = Config.Track.SegmentLength / Economy.walkSpeed(p, p.Surge, now)
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

	local overkill = Economy.overkill(p.Power, needed, p)
	OVER_SUM = (OVER_SUM or 0) + overkill
	RATIO_SUM = (RATIO_SUM or 0) + p.Power / math.max(needed, 1)
	RATIO_MAX = math.max(RATIO_MAX or 0, p.Power / math.max(needed, 1))
	-- Kolikrát se uplatnil strop. Strop je pojistka; když se uplatňuje
	-- běžně, přeplácnutí přestává být signálem a stává se konstantou.
	if p.Power / math.max(needed, 1) >= Config.Track.OverkillCap then
		CLAMPED = (CLAMPED or 0) + 1
	end

	--[[
		Nálet se váže na řetěz comba. Simulace jednotlivé řetězy nesleduje
		(pracuje s průměrným násobičem), takže se modeluje podílem:
		hráč drží řetěz `COMBO_UPTIME` času, a tolik zdí tedy prorazí
		s rozjetým řetězem. Rozhoduje se deterministicky přes počítadlo,
		aby byl běh opakovatelný.
	]]
	p.Clock = now + seconds
	SURGE_TICK = (SURGE_TICK or 0) + COMBO_UPTIME
	if SURGE_TICK >= 1 then
		SURGE_TICK -= 1
		p.Surge = p.Clock + Config.Track.SurgeSeconds
		SURGE_COUNT = (SURGE_COUNT or 0) + 1
	end

	--[[
		Power se průrazem NEODEČÍTÁ — na serveru je kumulativní přes celý
		svět (GameService.onSmash ho nechává být, nuluje se až dojetím kola
		nebo přechodem do jiného světa). Simulace to musí dělat stejně,
		jinak měří jinou hru, než jaká poběží.
	]]
	-- Zeď Power spotřebuje; přebytek si hráč nechává do další
	local coins = Economy.smashReward(p, p.Barrier, 0)
	p.Power = math.max(p.Power - needed, 0)
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
	buySquishies(p)

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

--[[
	Jak dlouho trvá první odměna.

	Roblox od konce roku 2025 řadí hry hlavně podle toho, jestli se hráč
	vrátí, a první minuta o tom rozhoduje víc než cokoliv dalšího —
	doporučení pro žánr je "první odměna do 60 sekund". Je to číslo,
	které se dá rozbít úpravou ceny první zdi, aniž by si toho někdo
	všiml, takže se měří.
]]
print(string.format("PRVNIZED=%.1f", clearBarrier(newPlayer())))

while t < LIMIT do
	t += clearBarrier(p)
	CLOCK = t
	shop(p)
	unlock(p, log, t)
end

print("=== Odemykani svetu ===")
for _, line in ipairs(log) do
	print("  " .. line)
end
print("")
print("=== Hracky ===")
for _, line in ipairs(TOY_LOG) do
	print("  " .. line)
end
print(string.format("KOUPENO=%d z %d", #TOY_LOG, #Live.forSale()))
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
print(string.format("POMER=%.0f prumerne, %.0f nejvyssi (strop %d)", (RATIO_SUM or 0) / math.max(BOUND_TOTAL or 1, 1), RATIO_MAX or 0, Config.Track.OverkillCap))
print(string.format("STROP=%d%% barier", math.floor((CLAMPED or 0) / math.max(BOUND_TOTAL or 1, 1) * 100)))
print(string.format("SURGE=%d%% barier", math.floor((SURGE_COUNT or 0) / math.max(BOUND_TOTAL or 1, 1) * 100)))
"""

MODE_REBIRTH = r"""
local p, t, count, previous = newPlayer(), 0, 0, 0
local shrinking, lastGap = 0, 0

print("=== Smycka rebirthu ===")
while t < LIMIT do
	t += clearBarrier(p)
	shop(p)
	unlock(p, nil, t)

	if Economy.canRebirth(p) then
		count += 1
		--[[
			Odstup od minulého rebirthu. Rebirth je žebřík, ne běžící
			pás: každý další má stát znatelně víc práce než ten
			předchozí. Kdyby odstupy klesaly nebo stály na místě, je
			z rebirthu jen tlačítko, které hráč mačká pořád dokola —
			a to je přesně ta chvíle, kdy hráči z her tohohle žánru
			odcházejí.
		]]
		local gap = t - previous
		print(string.format("  rebirth #%d v %6.0f min (%.1f h) -> nasobic %.2fx, odstup %.0f min",
			p.Rebirths + 1, t / 60, t / 3600,
			1 + (p.Rebirths + 1) * Config.Rebirth.BonusPerRebirth,
			gap / 60))

		if count > 1 and gap < lastGap * 0.9 then
			shrinking += 1
		end
		lastGap = gap
		previous = t

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

print(string.format("REBIRTHU=%d", count))
print(string.format("ZKRACENI=%d", shrinking))

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
    parser.add_argument(
        "--max-clamped",
        type=float,
        default=-1,
        help=(
            "selhat, když strop přeplácnutí (Config.Track.OverkillCap) zabírá "
            "u víc než tolika procent bariér. Strop je pojistka — když se "
            "uplatňuje běžně, je z přeplácnutí konstanta a Power, štěstí, "
            "pety i rebirth zase nemají kam ústit."
        ),
    )
    parser.add_argument(
        "--min-overkill",
        type=float,
        default=0,
        help=(
            "selhat, pokud průměrné přeplácnutí klesne pod tuhle hodnotu (pro CI). "
            "Přeplácnutí je jediná cesta, kterou se Power, štěstí, pety a combo "
            "propisují do peněz ve chvíli, kdy zdi padají na dotek — když spadne "
            "na 1, tyhle systémy zase přestanou cokoliv znamenat."
        ),
    )
    parser.add_argument(
        "--min-rebirths",
        type=int,
        default=0,
        help=(
            "selhat, pokud se za běh nedosáhne aspoň tolika rebirthů (jen s --rebirth). "
            "Jeden rebirth za den je málo: hráč se k trvalým perkům nedostane a celá "
            "větev stromu je pro něj dekorace."
        ),
    )
    parser.add_argument(
        "--max-shrinking",
        type=int,
        default=-1,
        help=(
            "kolik odstupů mezi rebirthy smí být KRATŠÍCH než ten předchozí (jen "
            "s --rebirth). Rebirth je žebřík, ne běžící pás — každý další má stát víc "
            "práce. Jedno zkrácení je v pořádku a čekané: první rebirth se dře bez "
            "jakéhokoliv násobiče, druhý už s ním. Víc jich znamená, že se smyčka "
            "zrychluje sama a přestává mít vrchol."
        ),
    )
    parser.add_argument(
        "--max-first-wall",
        type=float,
        default=0,
        help=(
            "selhat, pokud první zeď nováčkovi trvá déle než tolik sekund. "
            "První minuta rozhoduje o tom, jestli se hráč vrátí, a je to číslo, "
            "které se dá rozbít úpravou ceny první zdi, aniž by si toho někdo všiml."
        ),
    )
    parser.add_argument(
        "--all-toys",
        action="store_true",
        help=(
            "selhat, pokud si hráč za běh nekoupí všechny hračky z katalogu (pro CI). "
            "Žebříček hraček kopíruje pořadí levelů, takže hračka, na kterou se "
            "nedá dosáhnout, znamená level, jehož obří rekvizita hráči jen ukazuje "
            "něco, co si nikdy nekoupí."
        ),
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

        if args.min_overkill > 0:
            match = re.search(r"^OVERKILL=([\d.]+)x", result.stdout, re.M)
            overkill = float(match.group(1)) if match else 0
            if overkill < args.min_overkill:
                sys.stderr.write(
                    f"\nCHYBA: průměrné přeplácnutí {overkill}x, očekáváno aspoň "
                    f"{args.min_overkill}x. Power, štěstí, pety a combo se přestaly "
                    f"propisovat do peněz — viz oddíl 'Vada, kterou našlo až měření' "
                    f"v README.\n"
                )
                sys.exit(1)
            print(f"OK: přeplácnutí {overkill}x (minimum {args.min_overkill}x).")

        if args.all_toys:
            match = re.search(r"^KOUPENO=(\d+) z (\d+)$", result.stdout, re.M)
            bought = int(match.group(1)) if match else 0
            total = int(match.group(2)) if match else 0
            if match is None or bought < total:
                sys.stderr.write(
                    f"\nCHYBA: za {args.hours} h si hráč koupil {bought} z {total} hraček. "
                    f"Na zbytek se nedá dosáhnout, takže levely, které je ukazují, "
                    f"nabízejí zboží mimo hru.\n"
                )
                sys.exit(1)
            print(f"OK: koupeno všech {total} hraček.")

        if args.max_first_wall > 0:
            match = re.search(r"^PRVNIZED=([\d.]+)$", result.stdout, re.M)
            first = float(match.group(1)) if match else 1e9
            if first > args.max_first_wall:
                sys.stderr.write(
                    f"\nCHYBA: první zeď trvá nováčkovi {first} s, povoleno "
                    f"{args.max_first_wall} s. První minuta rozhoduje o tom, "
                    f"jestli se hráč vrátí.\n"
                )
                sys.exit(1)
            print(f"OK: první zeď za {first} s (nejvýš {args.max_first_wall} s).")

        if args.min_rebirths > 0:
            match = re.search(r"^REBIRTHU=(\d+)$", result.stdout, re.M)
            count = int(match.group(1)) if match else 0
            if count < args.min_rebirths:
                sys.stderr.write(
                    f"\nCHYBA: za {args.hours} h se dosáhlo {count} rebirthů, "
                    f"očekáváno aspoň {args.min_rebirths}. Trvalé perky jsou tím "
                    f"pro hráče nedosažitelné.\n"
                )
                sys.exit(1)
            print(f"OK: {count} rebirthů (minimum {args.min_rebirths}).")

        if args.max_shrinking >= 0:
            match = re.search(r"^ZKRACENI=(\d+)$", result.stdout, re.M)
            shrinking = int(match.group(1)) if match else 0
            if shrinking > args.max_shrinking:
                sys.stderr.write(
                    f"\nCHYBA: {shrinking} odstupů mezi rebirthy je kratších než ten "
                    f"předchozí, povoleno {args.max_shrinking}. Smyčka se zrychluje "
                    f"sama a přestává mít vrchol.\n"
                )
                sys.exit(1)
            print(f"OK: zkracujících se odstupů {shrinking} (nejvýš {args.max_shrinking}).")

        if args.max_clamped >= 0:
            match = re.search(r"^STROP=(\d+)%", result.stdout, re.M)
            clamped = float(match.group(1)) if match else 100
            if clamped > args.max_clamped:
                sys.stderr.write(
                    f"\nCHYBA: strop přeplácnutí zabírá u {clamped:.0f} % bariér, "
                    f"povoleno nejvýš {args.max_clamped:.0f} %. Zvedni "
                    f"Config.Track.OverkillCap — jinak je z přeplácnutí konstanta.\n"
                )
                sys.exit(1)
            print(f"OK: strop zabírá u {clamped:.0f} % bariér (nejvýš {args.max_clamped:.0f} %).")
    finally:
        pathlib.Path(path).unlink(missing_ok=True)


if __name__ == "__main__":
    main()

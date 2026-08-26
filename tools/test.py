#!/usr/bin/env python3
"""
Spouštěč testů.

Testuje dvě různé věci a každá potřebuje něco jiného:

  ČISTÁ LOGIKA (zámek profilu, obchod, omezovač volání) — moduly, které
  nesahají na Roblox API. Načtou se rovnou a otestují se přímo. Tyhle
  věci jsou schválně oddělené právě proto, aby to šlo.

  START HRY — načte se celý strom modulů proti náhradě Roblox prostředí
  (`tests/support/roblox.luau`) a nastartuje se server. Chytí to chyby,
  které kompilace nevidí: volání neexistující funkce na jiném modulu,
  špatný počet argumentů, překlep v názvu remotu.

Ta druhá část vznikla poté, co v projektu několik kol seděla chyba, kvůli
které hra nemohla naběhnout, a build byl celou dobu zelený.

Použití:
    python3 tools/test.py
"""

import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
TESTS = ROOT / "tests"
SUPPORT = TESTS / "support"


def luau_modules() -> dict[str, pathlib.Path]:
    """Všechny herní moduly podle jména souboru.

    Jména jsou v projektu jednoznačná, takže se `require` dá rozřešit
    podle posledního identifikátoru bez sledování proměnných."""
    modules: dict[str, pathlib.Path] = {}

    for path in sorted(SRC.rglob("*.luau")):
        name = path.stem
        # init.server / init.client nejsou moduly, ale vstupní body
        if name.startswith("init."):
            continue
        if name in modules:
            sys.exit(f"Dva moduly se jménem {name}: {modules[name]} a {path}")
        modules[name] = path

    return modules


def find_requires(text: str) -> list[tuple[int, int, str]]:
    """Najde `require(...)` včetně vnořených závorek."""
    found = []
    index = 0

    while True:
        start = text.find("require(", index)
        if start == -1:
            return found

        depth = 0
        position = start + len("require")

        while position < len(text):
            char = text[position]
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0:
                    found.append((start, position + 1, text[start + len("require(") : position]))
                    break
            position += 1
        else:
            return found

        index = position + 1


def resolve(expression: str) -> str:
    """Z výrazu v `require` vytáhne jméno modulu.

    Zvládá `script.Parent.Config`, `Shared.Config`,
    `script:WaitForChild("Effects")` i `script.Parent.UI.Style`."""
    quoted = re.findall(r'"(\w+)"', expression)
    if quoted:
        return quoted[-1]

    parts = re.findall(r"[\w]+", expression)
    if not parts:
        sys.exit(f"Nerozumím require({expression})")
    return parts[-1]


def rewrite(text: str) -> str:
    """Nahradí `require(cokoliv)` za `__require("Jméno")`."""
    for start, end, expression in reversed(find_requires(text)):
        text = text[:start] + f'__require("{resolve(expression)}")' + text[end:]
    return text


def build_script() -> str:
    modules = luau_modules()
    parts: list[str] = []

    # 1) Náhrada prostředí musí být první — moduly na ni sahají hned při načtení.
    #    Globály se navěsí do lokálních proměnných, protože `_G` je v Luau CLI
    #    jen ke čtení a moduly musí prostředí vidět ve svém uzávěru.
    parts.append("local __stub = (function()")
    parts.append((SUPPORT / "roblox.luau").read_text(encoding="utf-8"))
    parts.append("end)()")
    parts.append("local __env = __stub.build()")
    parts.append("local __world = __env._world")

    for name in (
        "Instance", "Enum", "Vector3", "Vector2", "Color3", "BrickColor", "CFrame", "UDim2", "UDim",
        "NumberSequence", "NumberSequenceKeypoint", "ColorSequence", "ColorSequenceKeypoint",
        "NumberRange", "TweenInfo", "PhysicalProperties", "Rect", "Random", "task",
        "game", "workspace",
    ):
        parts.append(f"local {name} = __env.{name}")

    # `script` používají vstupní body na hledání složek
    parts.append('local script = __stub.newInstance("Script", "Server")')

    # 2) Líné načítání modulů. Cyklické závislosti tak fungují stejně
    #    jako v Robloxu: `require` uvnitř funkce se vyhodnotí až při volání.
    parts.append("local __LOADERS = {}")
    parts.append("local __CACHE = {}")
    parts.append("""
local function __require(name)
	if __CACHE[name] ~= nil then
		return __CACHE[name]
	end
	local loader = __LOADERS[name]
	if not loader then
		error("Chybí modul: " .. name, 0)
	end
	local result = loader()
	__CACHE[name] = result
	return result
end
""")

    for name, path in modules.items():
        body = rewrite(path.read_text(encoding="utf-8"))
        parts.append(f'__LOADERS["{name}"] = function()')
        parts.append(body)
        parts.append("end")

    # 3) Vstupní body jako funkce, aby si je test pustil sám
    parts.append("local __ENTRIES = {}")
    #[[ Loading screen je taky vstupní bod: běží z ReplicatedFirst dřív
    #   než cokoliv jiného, takže chyba v něm znamená, že hráč uvidí
    #   černou obrazovku a víc nic. ]]
    for name, relative in (
        ("server", "src/server/init.server.luau"),
        ("loading", "src/loading/init.client.luau"),
    ):
        body = rewrite((ROOT / relative).read_text(encoding="utf-8"))
        parts.append(f'__ENTRIES["{name}"] = function()')
        parts.append(body)
        parts.append("end")

    # 4) Testovací rámec
    parts.append(HARNESS)

    # 5) Sady testů
    # Pole, ne mapa: `for k, v in mapa` jede v pořadí hashů, takže
    # přidání jediné sady přeházelo pořadí všech ostatních — a sady,
    # které na sebe nechtěně sahaly, jednou prošly a podruhé ne.
    parts.append("local SUITES = {}")
    for spec in sorted(TESTS.glob("*.spec.luau")):
        parts.append(f'table.insert(SUITES, {{ Name = "{spec.stem}", Run = (function()')
        parts.append(spec.read_text(encoding="utf-8"))
        parts.append("end)() })")

    parts.append(RUNNER)
    return "\n".join(parts)


HARNESS = r"""
local passed, failed = 0, 0
local failures = {}
local currentSuite = ""

local t = {}

-- Testy si moduly berou jménem nebo cestou; obojí vede na stejný zavaděč
function t.require(reference)
	local name = string.match(reference, "([%w_]+)%.luau$") or reference
	return __require(name)
end

--[[
	Nastartuje server, ale jen jednou za běh.

	Sady, které potřebují běžící služby (profily, remoty, postavený
	svět), si o to musí říct samy. Spoléhat na to, že server nastartuje
	nějaká jiná sada dřív, znamená testy, které procházejí jen v jednom
	pořadí — a to pořadí se mění s každým přidaným souborem.

	Chyba ze startu se pamatuje a hlásí **při každém** volání: jinak by
	spadla jen ta sada, která měla tu smůlu být první.
]]
local booted = false
local bootError = nil

function t.boot()
	if not booted then
		booted = true
		local ok, err = pcall(t.entry("server"))
		if not ok then
			bootError = err
		end
	end

	if bootError then
		error(bootError, 0)
	end
end

function t.entry(name)
	local entry = __ENTRIES[name]
	if not entry then
		error("Neznámý vstupní bod: " .. name, 0)
	end
	return entry
end

function t.world()
	return __world
end

function t.stub()
	return __stub
end

function t.test(name, body)
	local ok, err = pcall(body)
	if ok then
		passed += 1
		print("  ok   " .. name)
	else
		failed += 1
		print("  FAIL " .. name)
		table.insert(failures, currentSuite .. " > " .. name .. ": " .. tostring(err))
	end
end

function t.assert(condition, message)
	if not condition then
		error(message or "podmínka neplatí", 2)
	end
end

function t.equal(actual, expected, message)
	if actual ~= expected then
		error(string.format("%s: čekáno %s, dostal %s",
			message or "hodnota", tostring(expected), tostring(actual)), 2)
	end
end
"""

RUNNER = r"""
for _, suite in SUITES do
	currentSuite = suite.Name
	print(suite.Name)
	suite.Run(t)
end

print("")
print(string.format("%d prošlo, %d selhalo", passed, failed))

if failed > 0 then
	for _, line in failures do
		print("  " .. line)
	end
	error("Testy selhaly", 0)
end
"""


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


def main() -> None:
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as handle:
        handle.write(build_script())
        path = handle.name

    try:
        result = subprocess.run([find_luau(), path], capture_output=True, text=True, timeout=180)
        sys.stdout.write(result.stdout)
        if result.returncode != 0:
            sys.stderr.write(result.stderr)
        sys.exit(result.returncode)
    finally:
        pathlib.Path(path).unlink(missing_ok=True)


if __name__ == "__main__":
    main()

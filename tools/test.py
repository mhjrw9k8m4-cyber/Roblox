#!/usr/bin/env python3
"""
Spouštěč testů.

Roblox testy se normálně píšou tak, že se pustí hra. Tady jde o čistou
logiku bez engine API, takže se dá spustit rovnou v Luau — pár sekund
místo startu Studia, a hlavně to jde pustit v CI.

Testovat jde jen kód, který nesahá na Roblox API. To je záměr: kritická
rozhodnutí (zámek profilu, ekonomika) jsou schválně oddělená do čistých
funkcí právě proto, aby se dala ověřit.

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
TESTS = ROOT / "tests"

# Malý testovací rámec. Vlastní proto, že cokoliv hotového by potřebovalo
# balíčkovací nástroje a tady jde o pár desítek řádků.
HARNESS = r"""
local passed, failed = 0, 0
local failures = {}
local currentSuite = ""

local t = {}

function t.require(path)
	local module = MODULES[path]
	if not module then
		error("Chybí modul: " .. path)
	end
	return module
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

for name, suite in SUITES do
	currentSuite = name
	print(name)
	suite(t)
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

# Roblox API, které moduly potřebují jen jako data
STUB = """Color3 = { fromRGB = function() return {} end }
Enum = { Material = setmetatable({}, { __index = function(_, k) return k end }) }
"""


def module_body(relative: str) -> str:
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


def collect_modules(specs: list[pathlib.Path]) -> list[str]:
    """Posbírá moduly, které si testy vyžádaly přes t.require."""
    wanted = set()
    for spec in specs:
        wanted.update(re.findall(r't\.require\("([^"]+)"\)', spec.read_text(encoding="utf-8")))
    return sorted(wanted)


def main() -> None:
    specs = sorted(TESTS.glob("*.spec.luau"))
    if not specs:
        sys.exit("V tests/ nejsou žádné .spec.luau soubory.")

    parts = [STUB, "local MODULES = {}"]

    for relative in collect_modules(specs):
        parts.append(f'MODULES["{relative}"] = (function()')
        parts.append(module_body(relative))
        parts.append("end)()")

    parts.append("local SUITES = {}")
    for spec in specs:
        parts.append(f'SUITES["{spec.stem}"] = (function()')
        parts.append(spec.read_text(encoding="utf-8"))
        parts.append("end)()")

    parts.append(HARNESS)

    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as handle:
        handle.write("\n".join(parts))
        path = handle.name

    try:
        result = subprocess.run([find_luau(), path], capture_output=True, text=True, timeout=120)
        sys.stdout.write(result.stdout)
        if result.returncode != 0:
            sys.stderr.write(result.stderr)
        sys.exit(result.returncode)
    finally:
        pathlib.Path(path).unlink(missing_ok=True)


if __name__ == "__main__":
    main()

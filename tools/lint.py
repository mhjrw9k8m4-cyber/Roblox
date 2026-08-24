#!/usr/bin/env python3
"""
Statická kontrola věcí, které kompilátor neuvidí.

Luau je dynamický: `Remotes.Neexistuje` se v pohodě zkompiluje a spadne
až za běhu. Přesně tohle se v projektu stalo — osm remotů se používalo,
ale nebyly v definicích, takže by hra neběžela vůbec a kompilace o tom
mlčela.

Kontroluje:
  1. remoty použité v kódu, ale nedefinované  (chyba)
  2. remoty definované, ale nikde nepoužité   (varování)
  3. nepoužité importy                        (varování)
  4. `print(` v serverovém kódu               (varování)

Použití:
    python3 tools/lint.py
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
REMOTES = SRC / "shared" / "Remotes.luau"


def luau_files() -> list[pathlib.Path]:
    return sorted(SRC.rglob("*.luau"))


def defined_remotes() -> set[str]:
    text = REMOTES.read_text(encoding="utf-8")
    block = re.search(r"local DEFINITIONS[^{]*\{(.*?)\n\}", text, re.S)
    if not block:
        sys.exit("Nenašel jsem tabulku DEFINITIONS v Remotes.luau.")
    return set(re.findall(r'^\t(\w+)\s*=\s*"', block.group(1), re.M))


def check_remotes(errors: list[str], warnings: list[str]) -> None:
    defined = defined_remotes()
    used: dict[str, list[str]] = {}

    for path in luau_files():
        if path == REMOTES:
            continue
        text = path.read_text(encoding="utf-8")
        relative = path.relative_to(ROOT)

        # Přímé použití: Remotes.Neco
        for name in re.findall(r"Remotes\.(\w+)", text):
            used.setdefault(name, []).append(str(relative))

        # Nepřímé: klient volá invoke("Neco") a indexuje tabulku řetězcem.
        # Bez tohohle by se každý takový remote hlásil jako nepoužitý.
        for name in re.findall(r'"(\w+)"', text):
            if name in defined:
                used.setdefault(name, []).append(str(relative))

    for name, places in sorted(used.items()):
        if name not in defined:
            errors.append(f"Remote '{name}' se používá ({places[0]}), ale není v DEFINITIONS.")

    for name in sorted(defined - set(used)):
        warnings.append(f"Remote '{name}' je definovaný, ale nikde se nepoužívá.")


def check_imports(warnings: list[str]) -> None:
    for path in luau_files():
        text = path.read_text(encoding="utf-8")
        relative = path.relative_to(ROOT)

        for name in re.findall(r"^local (\w+) = require\(", text, re.M):
            # Jednou je samotná deklarace; víc znamená skutečné použití
            if len(re.findall(rf"\b{name}\b", text)) <= 1:
                warnings.append(f"{relative}: nepoužitý import '{name}'.")


#[[ `Remotes` je schválně dynamický: `__index` vytváří remoty za běhu
#    podle tabulky DEFINITIONS. Kontroluje ho `check_remotes`. ]]
DYNAMIC_MODULES = {"Remotes"}

# Přípona souboru se v textu tváří jako člen modulu (`Live.luau`)
IGNORED_MEMBERS = {"luau"}


def module_members(path: pathlib.Path) -> set[str]:
    """Co modul veřejně nabízí: funkce, datová pole i exportované typy."""
    text = path.read_text(encoding="utf-8")
    name = path.stem

    members = set(re.findall(rf"^function {name}[.:](\w+)", text, re.M))
    members |= set(re.findall(rf"^{name}\.(\w+)\s*=", text, re.M))
    # Exportované typy se používají stejným zápisem jako pole: `Assets.Layer`
    members |= set(re.findall(r"^export type (\w+)", text, re.M))

    return members


def check_members(errors: list[str]) -> None:
    """Ověří, že `Modul.neco` v kódu na tom modulu opravdu existuje.

    Tohle kompilátor neudělá: Luau je dynamický a `Economy.neexistuje`
    projde až do běhu. Přesně tak vypadala chyba s remoty."""
    shared = {path.stem: path for path in (SRC / "shared").glob("*.luau")}
    members = {name: module_members(path) for name, path in shared.items()}

    for path in luau_files():
        if path.parent.name == "shared":
            continue

        text = path.read_text(encoding="utf-8")
        relative = path.relative_to(ROOT)

        # Které lokální jméno odkazuje na který sdílený modul
        aliases: dict[str, str] = {}
        for alias, expression in re.findall(r"local (\w+) = require\(([^\n]+?)\)", text):
            target = re.findall(r"[\w]+", expression)
            if target and target[-1] in shared:
                aliases[alias] = target[-1]

        for alias, module in aliases.items():
            if module in DYNAMIC_MODULES:
                continue

            # Lookbehind na tečku: `Config.Track.Width` není `Track.Width`
            for member in re.findall(rf"(?<![.\w]){alias}\.(\w+)", text):
                if member in IGNORED_MEMBERS:
                    continue
                if member not in members[module]:
                    errors.append(
                        f"{relative}: {alias}.{member} — modul {module} nic takového nenabízí."
                    )


def check_prints(warnings: list[str]) -> None:
    for path in luau_files():
        text = path.read_text(encoding="utf-8")
        relative = path.relative_to(ROOT)

        for number, line in enumerate(text.splitlines(), start=1):
            stripped = line.strip()
            if stripped.startswith("--"):
                continue
            # `print` na startu je v pořádku, uvnitř smyčky zaplaví konzoli
            if re.search(r"\bprint\(", stripped) and "Server běží" not in stripped:
                warnings.append(f"{relative}:{number}: `print(` — jistě to tam má zůstat?")


def main() -> None:
    errors: list[str] = []
    warnings: list[str] = []

    check_remotes(errors, warnings)
    check_members(errors)
    check_imports(warnings)
    check_prints(warnings)

    for warning in warnings:
        print(f"  varování: {warning}")

    for error in errors:
        print(f"  CHYBA: {error}")

    print("")
    print(f"{len(errors)} chyb, {len(warnings)} varování, {len(luau_files())} souborů.")

    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()

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
  3. moduly použité, ale nerekvírované        (chyba)
  4. nepoužité importy                        (varování)
  5. `print(` v serverovém kódu               (varování)

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
    """Co modul veřejně nabízí: funkce, datová pole i exportované typy.

    Jméno tabulky se bere z `return` na konci souboru, ne z názvu souboru:
    `GuardService.luau` vrací tabulku `Guard`, takže podle stem by tu
    nebyl vidět jediný člen a kontrola by mlčky prošla vždycky.
    """
    text = path.read_text(encoding="utf-8")

    returned = re.findall(r"^return (\w+)\s*$", text, re.M)
    name = returned[-1] if returned else path.stem

    members = set(re.findall(rf"^function {name}[.:](\w+)", text, re.M))
    members |= set(re.findall(rf"^{name}\.(\w+)\s*=", text, re.M))
    # Exportované typy se používají stejným zápisem jako pole: `Assets.Layer`
    members |= set(re.findall(r"^export type (\w+)", text, re.M))

    return members


def check_members(errors: list[str]) -> None:
    """Ověří, že `Modul.neco` v kódu na tom modulu opravdu existuje.

    Tohle kompilátor neudělá: Luau je dynamický a `Economy.neexistuje`
    projde až do běhu. Přesně tak vypadala chyba s remoty.

    Platí na všechny moduly, ne jen na sdílené: klientské i serverové
    soubory se mezi sebou volají úplně stejně."""
    known = {path.stem: path for path in luau_files() if not path.stem.startswith("init")}
    members = {name: module_members(path) for name, path in known.items()}

    for path in luau_files():
        text = code_only(path.read_text(encoding="utf-8"))
        relative = path.relative_to(ROOT)

        # Které lokální jméno odkazuje na který modul
        aliases: dict[str, str] = {}
        for alias, expression in re.findall(r"local (\w+) = require\(([^\n]+?)\)", text):
            target = re.findall(r"[\w]+", expression)
            if target and target[-1] in known:
                aliases[alias] = target[-1]

        for alias, module in aliases.items():
            if module in DYNAMIC_MODULES or module == path.stem:
                continue

            # Lookbehind na tečku: `Config.Track.Width` není `Track.Width`
            for member in re.findall(rf"(?<![.\w]){alias}\.(\w+)", text):
                if member in IGNORED_MEMBERS:
                    continue
                if member not in members[module]:
                    errors.append(
                        f"{relative}: {alias}.{member} — modul {module} nic takového nenabízí."
                    )


def code_only(text: str) -> str:
    """Zahodí komentáře a řetězce — zbude jen to, co se opravdu spustí.

    Bez tohohle hlásí kontrola zmínku v komentáři (`viz GameService.worldCleared`)
    jako chybějící import.
    """
    text = re.sub(r"--\[\[.*?\]\]", "", text, flags=re.S)
    text = re.sub(r"--[^\n]*", "", text)
    text = re.sub(r'"[^"\n]*"', '""', text)
    text = re.sub(r"'[^'\n]*'", "''", text)
    return text


def check_unresolved(errors: list[str]) -> None:
    """Modul se používá, ale v souboru se nikde nerekvíruje.

    `SoundKit.playNamed(...)` bez `require` se zkompiluje a spadne až v
    okamžiku, kdy na ten řádek hra dojde — u efektu, který se pouští jednou
    za čas, klidně až po vydání. Přesně tohle se stalo u líhnutí vajec:
    lint hlásil nula chyb a kód byl mrtvý.
    """
    modules = {path.stem for path in luau_files()}
    modules -= {"init.client", "init.server"}

    for path in luau_files():
        text = code_only(path.read_text(encoding="utf-8"))
        relative = path.relative_to(ROOT)

        # Co je v souboru navázané: importy, lokálky, funkce, parametry
        bound = set(re.findall(r"\blocal\s+([\w, ]+?)\s*[=\n]", text))
        names = {piece.strip() for group in bound for piece in group.split(",")}
        names |= set(re.findall(r"\bfunction\s+(\w+)", text))
        names |= set(re.findall(r"\bfor\s+([\w, ]+?)\s+in\b", text))
        names |= set(re.findall(r"\bfunction\s*\(([^)]*)\)", text))
        names |= {piece.strip().split(":")[0].strip() for group in names for piece in group.split(",")}
        names.add(path.stem)

        for member in sorted(set(re.findall(r"(?<![.\w:])(\w+)\.\w+", text))):
            if member in modules and member not in names:
                errors.append(
                    f"{relative}: používá {member}.…, ale nikde ho nerekvíruje."
                )


def check_palette(warnings: list[str]) -> None:
    """Barva v paletě, kterou nikdo nečte.

    Paleta je jediné místo, kde se dá přidat "něco na později" a nikdy
    si toho nevšimnout — na rozdíl od funkce se nepoužitá barva nikde
    neprojeví. `Config.Theme.PanelTop` tam takhle ležela celou dobu,
    zatímco panely si horní hranu počítaly zesvětlením.
    """
    config = (SRC / "shared" / "Config.luau").read_text(encoding="utf-8")
    block = re.search(r"Config\.Theme = \{(.*?)\n\}", config, re.S)
    if not block:
        return

    names = re.findall(r"^\t(\w+)\s*=", block.group(1), re.M)
    blob = "\n".join(code_only(path.read_text(encoding="utf-8")) for path in luau_files())

    for name in names:
        # Definice se píše bez tečky (`PanelTop =`), takže se do počtu
        # nezapočítá — nula znamená opravdu nula použití
        if len(re.findall(rf"\.{name}\b", blob)) == 0:
            warnings.append(f"Barva Theme.{name} se nikde nepoužívá.")


def check_recipes(warnings: list[str]) -> None:
    """Zvukový recept, který se nikde nepřehraje.

    Ta samá kategorie jako nepoužitá barva: recept se dá přidat "na
    později" a nic na něj neupozorní. `Assets.Recipes.Land` takhle
    přežil zavedení zvuků terénu, které ho nahradily — přehrál se
    naposledy nikdy.

    Hledá se jméno v uvozovkách, protože recepty se pouštějí přes
    `playNamed("Neco")`; proto se tady na rozdíl od zbytku lintu
    řetězce NEodstraňují.
    """
    assets = (SRC / "shared" / "Assets.luau").read_text(encoding="utf-8")
    block = re.search(r"Assets\.Recipes = \{(.*?)\n\}", assets, re.S)
    if not block:
        return

    names = re.findall(r"^\t(\w+)\s*=\s*\{", block.group(1), re.M)
    blob = "\n".join(path.read_text(encoding="utf-8") for path in luau_files())

    for name in names:
        if len(re.findall(rf'"{name}"', blob)) == 0:
            warnings.append(f"Zvuk '{name}' je v Assets.Recipes, ale nikdo ho nepřehraje.")


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


def check_dead_exports(warnings: list[str]) -> None:
    """Exportovaná funkce, kterou nikdo nevolá.

    Nevolaná funkce sama o sobě nevadí — vadí to, co znamená. V tomhle
    projektu to vždycky znamenalo, že se něco odpojilo a nikdo si toho
    nevšiml: hračka, kterou žádný kód neuděloval, přepínač, který nikdo
    nepřepínal, dopočet, který si volající raději opsal.

    Hlásí se jako varování, ne chyba: přístupová funkce udržovaná jen
    pro test je legitimní a test se do prohledávaného seznamu počítá,
    takže stačí ji v testu opravdu použít."""
    files = luau_files() + sorted((ROOT / "tests").rglob("*.luau"))
    bodies = {path: code_only(path.read_text(encoding="utf-8")) for path in files}

    for path in luau_files():
        body = bodies[path]
        tail = re.search(r"^return (\w+)\s*$", body, re.M)
        if not tail:
            continue

        table = tail.group(1)
        for name in sorted(set(re.findall(rf"^function {table}[.:](\w+)", body, re.M))):
            # Volání se hledá přes tečku i dvojtečku, tedy včetně `self:jméno()`
            calls = sum(len(re.findall(rf"[.:]{name}\b", text)) for text in bodies.values())
            definitions = len(re.findall(rf"^function {table}[.:]{name}\b", body, re.M))
            if calls - definitions == 0:
                relative = path.relative_to(ROOT)
                warnings.append(f"{relative}: {table}.{name} nikdo nevolá — odpojené, nebo k smazání?")


CZECH_LETTERS = "áčďéěíňóřšťúůýžÁČĎÉĚÍŇÓŘŠŤÚŮÝŽ"

# Pole, jejichž obsah čte HRÁČ. Jméno dílu ani hláška do konzole sem nepatří.
PLAYER_FIELDS = ("Text", "Desc", "Detail", "Title", "Subtitle", "ButtonText", "Big")


def strip_comments(text: str) -> str:
    """Kód bez komentářů, ale SE STRING LITERÁLY — ty se tady zrovna hledají."""
    text = re.sub(r"--\[\[.*?\]\]", "", text, flags=re.S)
    return re.sub(r"--[^\n]*", "", text)


def check_czech(errors: list[str]) -> None:
    """Česky psaný text, který uvidí hráč.

    Hra běží anglicky — HUD, cedule, nápověda i hlášky. Čeština se do
    ní přesto dostala na čtyřech místech naráz: popisy všech pěti
    vylepšení, popisy všech sedmi perků, podtitulek panelu s hračkami
    a tři hlášky, které se rozesílají VŠEM hráčům na serveru.

    Poznat to jde jen okem, a to je přesně ten druh chyby, který
    v projektu psaném česky vydrží až do vydání. Vnitřní jména dílů
    a hlášky do konzole česky být můžou — hráč je nikdy neuvidí."""
    fields = "|".join(PLAYER_FIELDS)

    for path in luau_files():
        body = strip_comments(path.read_text(encoding="utf-8"))
        relative = path.relative_to(ROOT)

        for number, line in enumerate(body.splitlines(), start=1):
            if not re.search(rf"\b({fields})\s*=", line):
                continue
            for quoted in re.findall(r'"([^"\n]*)"|`([^`\n]*)`', line):
                text = quoted[0] or quoted[1]
                if any(letter in CZECH_LETTERS for letter in text):
                    errors.append(
                        f"{relative}:{number}: česky v textu pro hráče: \"{text.strip()[:60]}\""
                    )


def check_player_tables(errors: list[str]) -> None:
    """Tabulka klíčovaná hráčem, ze které se nikdy nic nemaže.

    Server běží týdny a hráči se střídají. Tabulka, do které se za
    každého jen přidává, tedy roste do konce života serveru — a je to
    ten druh chyby, který se na testovacím serveru se dvěma hráči
    neprojeví vůbec.

    Hlídá se jen to, že se z tabulky VŮBEC NĚKDE maže. Úklid často
    vede přes několik funkcí (`DataService.release`, `TradeService.cancel`),
    takže požadovat ho přímo v `PlayerRemoving` by hlásilo poplach na
    kódu, který je v pořádku."""
    for path in luau_files():
        if "server" not in path.parts:
            continue

        body = path.read_text(encoding="utf-8")
        relative = path.relative_to(ROOT)

        for name in re.findall(r"^local (\w+): \{ \[Player\]", body, re.M):
            if not re.search(rf"\b{name}\[[^\]]+\] = nil", body):
                errors.append(
                    f"{relative}: z tabulky '{name}' se nikdy nic nemaže — "
                    f"na dlouho běžícím serveru poroste donekonečna."
                )


def main() -> None:
    errors: list[str] = []
    warnings: list[str] = []

    check_remotes(errors, warnings)
    check_members(errors)
    check_unresolved(errors)
    check_czech(errors)
    check_player_tables(errors)
    check_imports(warnings)
    check_palette(warnings)
    check_recipes(warnings)
    check_prints(warnings)
    check_dead_exports(warnings)

    for warning in warnings:
        print(f"  varování: {warning}")

    for error in errors:
        print(f"  CHYBA: {error}")

    print("")
    print(f"{len(errors)} chyb, {len(warnings)} varování, {len(luau_files())} souborů.")

    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()

# ASMR Studio 🔪

Roblox hra v žánru „satisfying ASMR“ — krájíš a drtíš materiály, posloucháš
u toho zvuky, sbíráš peníze a odemykáš lepší nože a materiály. Celý svět
i rozhraní se staví z kódu, takže ve Studiu nemusíš nic klikat.

## Herní smyčka

1. Stojíš u své stanice, nad kterou se vznáší materiál.
2. Klikáš (nebo držíš) → každá rána ubere kus odolnosti, spustí efekt,
   zvuk a přičte peníze.
3. Rychlé rány za sebou stavějí **combo** až na 2× a víc — čím rychleji
   sekáš, tím výš stoupá i výška zvuku.
4. Když materiál praskne, dostaneš bonus a hned se objeví nový.
5. Za peníze kupuješ **nože** (rychlejší rozpad), **materiály**
   (hodnotnější, ale odolnější) a **vylepšení** (5 nekonečných větví).
6. **Rebirth** vynuluje postup výměnou za trvalý násobič výdělku.

Vedle toho běží **odměny za odehraný čas** — deset milníků od 2 minut po
4 hodiny, které se vyzvedávají ručně.

## Rozjetí ve Studiu

Projekt používá [Rojo](https://rojo.space) — kód žije v gitu a synchronizuje
se do Studia.

```bash
# 1. nástroje (Rojo, StyLua, Selene)
rokit install          # nebo: cargo install rojo

# 2. spusť server
rojo serve
```

Ve Studiu pak nainstaluj Rojo plugin, dej **Connect** a strom se naskládá sám.
Zmáčkni Play — svět, stanice i UI vzniknou při startu serveru.

Jednorázový build bez živé synchronizace:

```bash
rojo build -o ASMRStudio.rbxlx
```

### Než hru publikuješ

- V **Game Settings → Security** zapni **Enable Studio Access to API Services**,
  jinak nebude fungovat ukládání. Hra to pozná a hráči řekne, že se postup
  neuloží — nepřepíše mu ale uložená data nulami.

## Zvuky ⚠️

`SoundId` v `src/shared/Config.luau` jsou **placeholdery**. Roblox od audio
updatu nedovolí používat cizí nahrané zvuky, takže:

1. Nahraj si vlastní ASMR zvuky přes
   [Creator Dashboard](https://create.roblox.com/dashboard/creations) →
   Development Items → Audio.
2. Zkopíruj jejich ID do `Config.Tools[].SoundId` (zvuk čepele) a
   `Config.Objects[].SoundId` (zvuk materiálu).

Hra běží i bez nich — zvuk, který se nenačte, se tiše přeskočí, efekty
zůstanou. Výška tónu se dopočítává z `Pitch` a aktuálního comba, takže
jeden dobrý zvuk na materiál stačí.

## Struktura

```
src/
  shared/          → ReplicatedStorage.Shared (vidí server i klient)
    Config.luau      všechna čísla a texty hry
    Economy.luau     vzorce progrese (jeden zdroj pro server i UI)
    Remotes.luau     definice síťové komunikace
    Format.luau      zkracování čísel (12,4K / 3,1M)
    Build.luau       pomocníky pro stavbu dílů a UI
  server/          → ServerScriptService.Server
    Services/
      DataService.luau      DataStore, autosave, odolnost proti výpadku
      WorldService.luau     postaví hub, osvětlení a atmosféru
      StationService.luau   přiděluje stanice, spawnuje materiál
      ASMRService.luau      rány, combo, odměny, auto-řez
      ShopService.luau      nákupy, nasazování, rebirth
      PlaytimeService.luau  odměny za odehraný čas
      ToolService.luau      čepel v ruce + leaderstats
  client/          → StarterPlayer.StarterPlayerScripts.Client
    Effects.luau     částice, plátky, otřes kamery, zvuk
    UI/              HUD, panely obchodu, notifikace
tools/
  simulate.py      simulace ekonomiky (viz níž)
```

## Ovládání

| Akce | Klávesnice / myš | Mobil |
|---|---|---|
| Seknout | levé tlačítko nebo mezerník / `E` (jde držet) | tlačítko **SEKNI** |
| Nože | `1` | tlačítko vpravo |
| Materiály | `2` | tlačítko vpravo |
| Vylepšení | `3` | tlačítko vpravo |
| Odměny | `4` | tlačítko vpravo |
| Rebirth | `5` | tlačítko vpravo |
| Zavřít panel | `Esc` | ✕ |

## Ladění ekonomiky

Ceny v Configu **nejsou odhad** — dopočítala je simulace tak, aby odemykání
vycházelo na tyhle časy aktivního hraní:

| Milník | Čas |
|---|---|
| Kuchyňský nůž | 3 min |
| Řeznická sekáčka | 12 min |
| Katana | 45 min |
| Diamantová čepel | 2 h |
| Neonová čepel | 4,5 h |
| Kvantový řezák | 9,5 h |
| Hvězdný prach (poslední materiál) | 21 h |
| 1. rebirth | 3 h |
| Max úroveň (50) | 6,6 h |

Po každé změně čísel v `Config.luau` si to ověř:

```bash
python3 tools/simulate.py              # kdy se co odemkne
python3 tools/simulate.py --rebirth    # smyčka rebirthů
```

Skript pouští **skutečné moduly hry** (`Config` + `Economy`) mimo Roblox,
takže neměří kopii vzorců, ale to, co opravdu poběží. Potřebuje binárku
[`luau`](https://github.com/luau-lang/luau/releases) v PATH.

### Na co si dát pozor

- **Poměr hodnota/odolnost** materiálů roste 1,6× za tier. Když ho zvedneš
  víc, příjem přeroste ceny a celý obsah se vyčerpá za necelou hodinu —
  přesně to se stalo první verzi čísel.
- **`Id` položek se nikdy nemění** — ukládají se do DataStore. Přejmenovat
  jde `Name`, ne `Id`.
- Přidání nové položky do `Config.Tools` / `Config.Objects` / `Config.Upgrades`
  stačí; obchod i ekonomika se o ni postarají samy.

## Co je hotové

- [x] Svět, stanice a osvětlení generované kódem
- [x] Krájení s combem, efekty, zvuky, otřes kamery
- [x] Peníze, XP a úrovně
- [x] 7 nožů, 9 materiálů, 5 větví vylepšení
- [x] Auto-řez (pasivní příjem)
- [x] Rebirth s trvalým násobičem
- [x] 10 odměn za odehraný čas
- [x] Ukládání přes DataStore s autosave a odolností proti výpadku
- [x] Leaderstats, mobilní ovládání, notifikace

### Kam dál

- Vlastní ASMR zvuky (viz výše) — největší dopad na pocit ze hry
- Gamepassy / vývojářské produkty (×2 peníze, auto-řez zdarma)
- Denní odměny a žebříček nejlepších hráčů přes `OrderedDataStore`
- Kosmetika: skiny čepelí, stopy, efekty rozpadu

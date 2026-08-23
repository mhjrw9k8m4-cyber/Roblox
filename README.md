# Power Smash 💥

Roblox hra ve stylu **„+1 Power"** her (Cars VS Tape, Keyboard Escape, Cut Grass).
Běžíš chodbou, sbíráš `+1 Power`, a když ho máš dost, prorazíš bariéru — ta se
s ASMR zvukem rozsype na střepy. Za průrazy jsou peníze, za peníze vylepšení,
za vylepšení rychlejší růst Poweru. A pořád dokola.

Celý svět i rozhraní se staví z kódu, takže ve Studiu se nemusí nic klikat.

## Herní smyčka

1. Sbíráš svítící `+1` kostky — každá přidá Power.
2. Cesta je přehrazená bariérou s požadavkem, třeba `120 POWER`.
   Nemáš dost → nepustí tě a ukáže, kolik chybí.
   Máš dost → **prorazíš** a tabule se rozletí na kusy.
3. Za každou bariéru jsou peníze, za celé kolo (12 bariér) bonus a gemy.
4. Peníze jdou do **vylepšení**: Power, Magnet, Speed, Luck, Auto Collect.
5. Za peníze si kupuješ **další svět** — větší čísla, jiný materiál, jiný zvuk.
6. **Rebirth** resetuje běh výměnou za trvalý násobič.

Vedle toho běží: **truhla zdarma** každých 90 s, **offline výdělky**
(35 % příjmu, strop 8 h), **boosty za gemy** (×2 Power, ×2 Coins, Auto Collect)
a **tituly nad hlavou** za počet průrazů.

### Proč se Power při změně světa nuluje

Power je postup v rámci jednoho světa, ne trvalé bohatství. Kdyby se přenášel,
vešel bys do nového světa s hotovými bariérami a přeskočil jeho obsah.
Trvalý postup drží peníze, vylepšení a rebirthy.

## Rozjetí ve Studiu

Projekt používá [Rojo](https://rojo.space) — kód žije v gitu a synchronizuje se
do Studia.

```bash
rokit install     # nainstaluje Rojo, StyLua, Selene
rojo serve
```

Ve Studiu nainstaluj Rojo plugin, dej **Connect** a strom se naskládá sám.
Pak Play — světy, tratě i UI vzniknou při startu serveru.

Jednorázový build: `rojo build -o PowerSmash.rbxlx`

### Než hru publikuješ

V **Game Settings → Security** zapni **Enable Studio Access to API Services**,
jinak nebude fungovat ukládání. Hra to pozná a hráči to řekne — nepřepíše mu
ale uložený postup nulami.

## Zvuky ⚠️

`SmashSound` v `src/shared/Config.luau` jsou **placeholdery**. Roblox nedovolí
používat cizí nahrané audio, takže:

1. Nahraj si vlastní ASMR zvuky přes
   [Creator Dashboard](https://create.roblox.com/dashboard/creations) →
   Development Items → Audio.
2. ID doplň do `Config.Worlds[].SmashSound`. Každý svět má svůj zvuk a `Pitch`,
   takže sklo zní jinak než čokoláda.

Hra běží i bez nich — zvuk, který se nenačte, se tiše přeskočí a efekty zůstanou.

## Struktura

```
src/
  shared/          → ReplicatedStorage.Shared (vidí server i klient)
    Config.luau      všechna čísla a texty hry
    Track.luau       geometrie tratě spočítaná, ne postavená
    Economy.luau     vzorce progrese (jeden zdroj pro server i UI)
    Remotes.luau     definice síťové komunikace
    Format.luau      zkracování čísel (12.4K / 3.1M)
    Build.luau       pomocníky pro díly a UI
  server/          → ServerScriptService.Server
    Services/
      DataService.luau    DataStore, autosave, odolnost proti výpadku
      WorldService.luau   postaví tratě všech světů
      GameService.luau    sbírání, validace průrazů, Power, auto-collect
      ShopService.luau    vylepšení, světy, boosty, tituly, rebirth, truhla
      PlayerService.luau  cedulka s titulem, leaderstats, offline výdělky
  client/          → StarterPlayer.StarterPlayerScripts.Client
    TrackView.luau   lokální pickupy a bariéry + hlavní herní smyčka
    Effects.luau     střepy, částice, rázová vlna, otřes kamery, zvuk
    UI/              HUD, panely, notifikace, widgety
tools/
  simulate.py      simulace ekonomiky (viz níž)
```

### Proč jsou pickupy a bariéry stavěné na klientovi

Bariéra musí blokovat každého hráče podle **jeho** postupu a sebraný pickup
musí zmizet jen tomu, kdo ho sebral. Díl vytvořený na klientovi existuje jen
u něj, takže jeho fyzika i viditelnost jsou automaticky „per hráč" — sdílená
geometrie by to neuměla.

Server na to ale nespoléhá. U každého sebraného pickupu ověří vzdálenost,
respawn a to, že hráč vůbec smí být tak daleko v trati; u každého průrazu
ověří pořadí bariéry, vzdálenost a skutečný Power. Klient tedy určuje jen
to, co **vidí**, ne to, co **dostane**.

## Ovládání

| Akce | Klávesnice / myš | Mobil |
|---|---|---|
| Pohyb, sbírání | WASD (sbírá se automaticky dotykem) | joystick |
| Prorazit bariéru | doběhnout k ní s dostatkem Poweru | stejně |
| Upgrades | `1` | tlačítko vlevo |
| Worlds | `2` | tlačítko vlevo |
| Titles | `3` | tlačítko vlevo |
| Rebirth | `4` | tlačítko vlevo |
| Zavřít panel | `Esc` | ✕ |

## Ladění ekonomiky

Ceny světů a rebirthu **nejsou odhad** — dopočítala je simulace na tyhle časy
aktivního hraní:

| Milník | Čas |
|---|---|
| Jelly Cave | 12 min |
| Ice Vault | 48 min |
| Chocolate Factory | 2,2 h |
| Neon Core | 5,2 h |
| Void Prism | 11,2 h |
| 1. rebirth | 2,8 h |
| 5. rebirth | 21 h |

Po každé změně čísel v `Config.luau` si to ověř:

```bash
python3 tools/simulate.py              # kdy se odemknou světy
python3 tools/simulate.py --rebirth    # smyčka rebirthů
python3 tools/simulate.py --hours 6    # kratší běh
```

Skript pouští **skutečné moduly hry** (`Config`, `Track`, `Economy`) mimo
Roblox, takže neměří kopii vzorců, ale to, co opravdu poběží. Potřebuje
binárku [`luau`](https://github.com/luau-lang/luau/releases) v PATH nebo
v `tools/`.

### Na co si dát pozor

- **Bariéry se odvozují od `Pickup` daného světa.** Díky tomu se každý svět
  hraje stejně a tempo určují vylepšení, ne skok na další svět. Kdyby se
  `BarrierBase` mezi světy rozešel, jeden svět by byl triviální a jiný zeď.
- **Simulace počítá i čas na doběhnutí** k další bariéře. Bez toho tvrdila,
  že se celá hra dá projít za tři minuty.
- **`Id` položek se nikdy nemění** — ukládají se do DataStore. Přejmenovat
  jde `Name`, ne `Id`.
- Přidání světa, vylepšení, boostu nebo titulu do `Config` stačí; UI i
  ekonomika se o ně postarají samy.

## Co je hotové

- [x] Šest světů s vlastní barvou, materiálem, zvukem a měřítkem čísel
- [x] Sbírání `+1` s magnetem, Luck kritem a auto-collectem
- [x] Prorážení bariér s rozpadem na střepy, částicemi a otřesem
- [x] Peníze, gemy, 5 větví vylepšení
- [x] Rebirth s trvalým násobičem
- [x] Boosty za gemy, truhla zdarma, offline výdělky
- [x] Tituly nad hlavou, leaderstats
- [x] DataStore s autosave a odolností proti výpadku
- [x] Serverová validace všeho, co klient hlásí

### Kam dál

- Vlastní ASMR zvuky (viz výše) — největší dopad na pocit ze hry
- Gamepassy: ×2 Coins natrvalo, Auto Collect zdarma, VIP svět
- Denní odměny a žebříček přes `OrderedDataStore`
- Kosmetika: stopy za hráčem, skiny bariér, efekty průrazu

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

## Zvuky 🔊

**Hra zní hned, bez jediného nahrávání.** Roblox od audio updatu nedovolí použít
cizí nahrané audio — `rbxassetid://` od jiného tvůrce se v tvé hře nepřehraje.
Proto zvuky stojí na `rbxasset://`, což nejsou nahrané assety, ale soubory,
které Roblox posílá v **každém klientu**. Jsou vždycky dostupné a nikomu nepatří.

Těch souborů je jen pár, ale to nevadí, protože ASMR pocit nedělá jeden dokonalý
sample — dělá ho **vrstvení**. Jeden krok přehraný třikrát v různých výškách
a s posunem o setiny sekundy zní jako praskající sklo. Ten samý krok hluboko
a pomalu zní jako dopad čokoládové desky. Recepty jsou v `src/shared/Assets.luau`:

```lua
Ice = {   -- led: křupavé praskání, hodně krátkých úderů rychle za sebou
    { Id = STEP, Pitch = 3.2, Volume = 0.5 },
    { Id = STEP, Pitch = 2.9, Volume = 0.4, Delay = 0.03 },
    { Id = STEP, Pitch = 3.6, Volume = 0.35, Delay = 0.06 },
    { Id = LAND, Pitch = 2.2, Volume = 0.35, Delay = 0.02 },
}
```

Sbírání `+1` má navíc **stoupající stupnici**: čím rychleji sbíráš, tím výš tón
leze, a po pauze spadne zpátky. Stupnice je durová pentatonika, takže se to
nikdy nerozladí. Tohle je ten návykový prvek, kvůli kterému se v žánru sbírá.

### Vlastní ASMR nahrávky

Až si nahraješ vlastní přes
[Creator Dashboard](https://create.roblox.com/dashboard/creations) →
Development Items → Audio, stačí jediná tabulka:

```lua
Assets.Override = {
    Smash_Glass = "rbxassetid://TVOJE_ID",
    Pickup      = "rbxassetid://TVOJE_ID",
}
```

Recept se nahradí tvým zvukem, zbytek zůstane. Zvuk, který se nenačte,
se tiše přeskočí — hra kvůli němu nikdy nespadne.

## Textury a pohyb

Žádná textura se nenahrává, a přesto se všechno hýbe:

| Efekt | Jak je udělaný |
|---|---|
| Energetické pole na bariéře | Svislé `Beam`y s `TextureSpeed` — Beam bez obrázku je plný barevný pruh, takže proudí i bez assetu |
| Pulzování bariéry | Barva dýchá tím rychleji, čím blíž je proražení — postup vidíš, i když se nedíváš na UI |
| Tekoucí pruhy na podlaze | Neonové díly, které se posouvají k bariéře a ukazují, kam běžet |
| Posouvající se textury | `OffsetStudsU/V` — klasická technika na tekoucí energii. Zapne se sama, jakmile do `Assets.Textures` doplníš vlastní obrázek |

### Pohyby postavy

Taky celé kódem, protože nahraná animace by znamenala cizí `rbxassetid://`:

- **náklon při běhu** — otočení `RootJoint.C0`
- **houpání kamery** — `Humanoid.CameraOffset`
- **nabíjecí póza** — ramena dozadu, když máš dost Poweru na průraz
- **odraz při průrazu** — ruce dopředu, postava se protáhne, u nohou vyletí prstenec
- **dřep při dopadu** — krátké smáčknutí přes `BodyHeightScale`
- **rychlostní čáry a stopa** — zapnou se samy při vysoké rychlosti, barví se podle světa

Klíčový detail: pózy jdou přes **`Motor6D.C0`**, ne `Transform`. `Transform`
každý snímek přepíše Animator, takže by se pózy okamžitě smazaly. `C0` je
základní posun kloubu, který se s běžící animací sčítá — pózy se tak na
výchozí animaci navrství, místo aby s ní bojovaly.

## Struktura

```
src/
  shared/          → ReplicatedStorage.Shared (vidí server i klient)
    Config.luau      všechna čísla a texty hry
    Track.luau       geometrie tratě spočítaná, ne postavená
    Economy.luau     vzorce progrese (jeden zdroj pro server i UI)
    Assets.luau      zvukové recepty a textury (viz kapitola Zvuky)
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
    Effects.luau     střepy, částice, rázová vlna, otřes kamery
    SoundKit.luau    vrstvený přehrávač + stoupající stupnice
    Textures.luau    energetické pole, tekoucí pruhy, pulzování
    CharacterFX.luau procedurální pohyby postavy
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
- [x] ASMR zvuky bez nahrávání — vrstvené recepty na `rbxasset://`
- [x] Animované textury: energetické pole, tekoucí pruhy, pulzování
- [x] Procedurální pohyby postavy bez nahraných animací

### Kam dál

- Vlastní ASMR nahrávky přes `Assets.Override` — hra zní i bez nich,
  ale vlastní samply jsou pořád největší skok v kvalitě
- Gamepassy: ×2 Coins natrvalo, Auto Collect zdarma, VIP svět
- Denní odměny a žebříček přes `OrderedDataStore`
- Kosmetika: stopy za hráčem, skiny bariér, efekty průrazu

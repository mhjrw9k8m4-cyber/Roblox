# Launch checklist

Co udělat, než hru pustíš mezi lidi, a proč zrovna to. Není to seznam
zbožných přání — je postavený na tom, co Roblox v roce 2026 skutečně
odměňuje v doporučování.

---

## Jak se dneska hry dostávají nahoru

Roblox na konci roku 2025 přepsal signály za domovskou stránkou. Tři věci,
které z toho plynou:

**1. Řadí retence, ne počet hráčů online.**
Model sleduje návraty ve třech oknech: den 1, dny 2–7 a dny 8–28. Hra
s dvěma sty hráči, kteří se vracejí, poroste rychleji než hra s dvěma
tisíci, kteří se nevrátí.

Cíle, na které mířit:

| Metrika | Slabé | Dobré | Skvělé |
|---|---|---|---|
| D1 retence | pod 15 % | 20 % | 30 %+ |
| D7 retence | pod 5 % | 8 % | 15 %+ |
| D30 retence | pod 2 % | 3 % | 7 %+ |

**2. Délka sezení se počítá jen do hodiny denně.**
Doporučovací bonus se zastropuje na prvních 60 minutách denního hraní
na hráče. Nafukovat playtime nemá smysl — proto v téhle hře **schválně
není žádný anti-AFK skript**. Nejenže by nepomohl, ale zkresluje ti
vlastní čísla, podle kterých se rozhoduješ.

**3. Útrata se měří samostatně.**
Dřív byla schovaná v jednom společném čísle, teď je to vlastní signál.
Proto ve hře monetizace je — ale žádná nabídka neblokuje postup, jen ho
zrychluje. Hra, která si postup drží za výplatou, prohraje na retenci
víc, než získá na útratě.

---

## Co v téhle hře drží hráče

Každý systém tady existuje kvůli konkrétnímu oknu retence:

| Systém | Řeší | Kde je v kódu |
|---|---|---|
| Loading screen s tipy | první dojem | `src/loading/` |
| Nápověda pro první sezení | D1 — pochopit smyčku do minuty | `src/client/Onboarding.luau` |
| Truhla zdarma každých 90 s | délka sezení | `ShopService.claimChest` |
| Denní odměna se sérií (7 dní) | D1 a D7 — sedmý den je ta meta | `RetentionService` |
| Denní úkoly (3 na den) | délka sezení a druhá série | `RetentionService` |
| Kódy | návrat po každém videu | `Live.Codes` |
| Squishy hračky | držení násobí Power, mačkání ho sype | `SquishyService` |
| Offline výdělky | důvod se vrátit zítra | `PlayerService.grantOffline` |
| Žebříček | sociální motivace | `LeaderboardService` |
| Rebirth | nekonečná smyčka pro ty, co dohráli | `ShopService.rebirth` |

Dvě série (přihlášení a úkoly) běží vedle sebe schválně. Když hráč jednu
přeruší, druhá ho pořád má čím vrátit.

---

## Než zmáčkneš publish

### 1. Zapni ukládání
**Game Settings → Security → Enable Studio Access to API Services.**
Bez toho nefunguje DataStore. Hra to pozná a hráči to řekne, ale postup
se neuloží.

### 2. Doplň ID

V `src/shared/Live.luau` jsou tři místa s nulami. Dokud tam nula zůstane,
věc se hráči prostě nezobrazí — nikdy neuvidí tlačítko, po kterém se nic
nestane.

- `Live.Passes[].GamepassId` — gamepassy
- `Live.Products[].ProductId` — vývojářské produkty
- `Live.Badges[].BadgeId` — odznaky za milníky

Badge vytvoř aspoň tři: první zeď, první rebirth, třetí svět. Zobrazují se
na profilu hry a fungují jako sociální důkaz.

### 3. Nahraj vlastní zvuky
Viz kapitola *Zvuky* v hlavním README. Hra zní i bez nich, ale vlastní
ASMR samply jsou největší jednotlivý skok v kvalitě, jaký můžeš udělat.

---

## Název, ikona, thumbnaily

Žánr má vlastní SEO gramatiku a vyplatí se ji dodržet — lidi hry v tomhle
stylu hledají přesně těmito slovy.

**Název:** `[X2] +1 Power Smash Wall`

- Hranatá závorka na začátku nese aktuální akci (`[X2]`, `[UPDATE]`,
  `[NEW WORLD]`). Mění se s každým updatem, aby karta vypadala živě.
- `+1` a sloveso jsou to, co lidi opravdu píšou do hledání.
- Drž do 50 znaků, jinak se konec ořízne.

**Ikona:** jeden objekt, obří číslo, silný obrys. Musí být čitelná
na 128 px na mobilu — tam ji uvidí většina lidí. Žádné dlouhé texty.

**Thumbnaily:** první je nejdůležitější, ostatní vidí málokdo.
Ukaž na něm **hráče uprostřed akce** a to největší číslo, jaké hra umí.
Dej tam progresi (`+800 → +12K → +99M`) — sděluje smyčku bez čtení.

**Popis:** první dva řádky jsou vidět bez rozkliknutí. Do nich patří,
co se ve hře dělá, ne uvítání. Pod to seznam kódů — hráči se kvůli němu
do popisu vracejí.

---

## Po vydání

**Updatuj každý týden až dva.** Kadence je pro retenci důležitější než
velikost updatu. Nový svět, nová sada hraček, nová sada kódů.

**S každým updatem vydej kód.** Je to nejlevnější způsob, jak přivést
zpátky lidi, kteří přestali hrát.

**Sleduj D1 a D7, ne CCU.** Když D1 spadne po updatu, něco jsi rozbil
v prvních minutách hraní — a tam se rozhoduje o všem ostatním.

**Než něco vyladíš, pusť simulaci.**

```bash
python3 tools/simulate.py            # kdy se odemknou světy
python3 tools/simulate.py --rebirth  # smyčka rebirthů
```

Běží na skutečných modulech hry, takže neměří kopii vzorců, ale to,
co opravdu poběží.

---

## Zdroje

- [Jak funguje doporučování v roce 2026](https://rolearn.dev/insights/roblox-game-discovery-algorithm-2026/)
- [Co algoritmus odměňuje (a co ne)](https://rowatcher.com/news/what-the-roblox-algorithm-actually-rewards-in-2026-not-ccu)
- [Benchmarky retence podle žánru](https://bloxg.com/statistics/roblox-retention-benchmarks)
- [Retence prvního týdne](https://rolearn.dev/guidance/first-week-retention-optimization/)
- [Discovery — oficiální dokumentace](https://create.roblox.com/docs/discovery)

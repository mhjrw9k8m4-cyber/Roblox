# Power Smash 💥

Roblox hra ve stylu **„+1 Power"** her (Cars VS Tape, Keyboard Escape, Cut Grass).
Běžíš chodbou, sbíráš `+1 Power`, a když ho máš dost, prorazíš bariéru — ta se
s ASMR zvukem rozsype na střepy. Za průrazy jsou peníze, za peníze vylepšení,
za vylepšení rychlejší růst Poweru. A pořád dokola.

Celý svět i rozhraní se staví z kódu, takže ve Studiu se nemusí nic klikat.

## Herní smyčka

1. Sbíráš svítící `+1` kostky — každá přidá Power.
2. Sbírání za sebou staví **combo**: do stovky článků, na stropu ×2 na
   každý pickup. Zastavíš se na dvě a půl vteřiny a řetěz spadne.
3. Cesta je přehrazená bariérou s požadavkem, třeba `120 POWER`.
   Nemáš dost → nepustí tě a ukáže, kolik chybí.
   Máš dost → **prorazíš** a tabule se rozletí na kusy.
4. Za každou bariéru jsou peníze — a čím **víc Poweru** jsi u ní měl, než
   kolik bylo potřeba, tím víc (přeplácnutí, viz níž).
5. Za celé kolo (12 bariér) je bonus a gemy. Svět pak jedeš znovu, ale
   zdi povyskočí: druhé kolo není totéž co první.
6. Peníze jdou do **vylepšení**: Power, Magnet, Speed, Luck, Auto Collect.
7. Za peníze si kupuješ **další svět** — větší čísla, jiný materiál, jiný zvuk.
8. **Rebirth** resetuje běh výměnou za trvalý násobič **a token** do stromu
   trvalých perků.

Vedle toho běží celá retenční vrstva: **denní odměna se sérií** (7 dní,
sedmý je ta meta), **tři denní úkoly** s vlastní sérií, **pety z vajec**,
**kódy**, **truhla zdarma** každých 90 s, **offline výdělky**, **boosty
za gemy**, **žebříček** a **tituly nad hlavou**.

Proč zrovna tyhle: Roblox od konce roku 2025 řadí hry podle retence, ne
podle počtu hráčů online. Podrobně i s čísly, na která mířit, je to
v [`docs/LAUNCH.md`](docs/LAUNCH.md).

### Proč se Power při změně světa nuluje

Power je postup v rámci jednoho světa, ne trvalé bohatství. Kdyby se přenášel,
vešel bys do nového světa s hotovými bariérami a přeskočil jeho obsah.
Trvalý postup drží peníze, vylepšení a rebirthy.

## Vada, kterou našlo až měření

Simulace hlásí u každého běhu i tohle:

```
BEH=99% (70518 z 70717 barier)
```

Tolik bariér padlo dřív, než k nim hráč vůbec **doběhl**. Jinými slovy:
zdi se nesundávaly sbíráním, ale během. A z toho plyne nepříjemný důsledek —
Power, Magnet, Luck, pety ani rebirth nedělaly nic. Všechny zvyšovaly
Power, jenže Poweru byl stejně přebytek. Jediná statistika, na které
záleželo, byla rychlost běhu.

Kompilace to nevidí, testy to neviděly a v UI to vypadalo v pořádku:
čísla rostla, kupovaly se úrovně, jen to nemělo žádný účinek.

Zkusil jsem to spravit tím, že zdi porostou s každým dojetým kolem světa.
Nefungovalo to a stojí za to říct proč: požadavek rostl exponenciálně,
zatímco hráčův příjem Poweru je **shora omezený** (úrovně vylepšení mají
strop, pety taky, rebirth roste lineárně). Exponenciála lineárku vždycky
přeroste, takže se hra po pár desítkách kol zastavila úplně — v jednom
měření hráč za 60 hodin prorazil 41 zdí. Zastropovat kola zas mechaniku
zrušilo.

Ven z toho vede **přeplácnutí**: kolikrát víc Poweru jsi u zdi měl, než
kolik bylo potřeba, se propíše do výplaty. Ne přímou úměrou, ale
odmocninou — stokrát víc Poweru dá desetkrát víc peněz, ne stokrát.

Tím se to srovnalo:

| Co zlepšuješ | Co ti to doopravdy dá |
|---|---|
| Speed, Magnet, Auto | víc zdí za minutu |
| Power, Luck, pety, rebirth, combo | víc peněz za každou zeď |

Zdi teď smí padat na dotek — je to ta správná odměna za grind — a přitom
každý systém ve hře pořád k něčemu je. Kola světů zůstala, protože dělají
druhý průjezd jiným než první, ale těžit se z nich nemusí.

Simulace obě čísla (`BEH` a `OVERKILL`) tiskne po každém běhu, aby tahle
vada nemohla znovu tiše vzniknout.

### A potřetí: strop, který se stal stropem

Přeplácnutí mělo `OverkillCap = 100` — pojistku proti tomu, aby se
z přebytku Poweru nestal hlavní zdroj příjmu.

Jenže skutečný poměr „kolik Poweru mám ku kolik potřebuju" je průměrně
kolem **600** a špičkově **desetitisíce**. Strop se tedy uplatnil skoro
u každé zdi a z přeplácnutí byla konstanta ×10. Tím se tiše vrátila
přesně ta vada, kvůli které přeplácnutí vzniklo: Power, štěstí, pety
a rebirth zase neměly kam ústit.

Poznalo se to náhodou — nálet měl práh nad běžným přeplácnutím a
nespustil se **ani jednou**, protože přeplácnutí nemohlo přes 10 přelézt.

Strop je teď 50 000 a simulace hlásí, u kolika procent zdí se uplatní.
CI selže, když to překročí 5 %:

```
STROP=0% barier
OK: strop zabírá u 0 % bariér (nejvýš 5 %).
```

Poučení, které se v tomhle projektu opakuje: **pojistka, která zabírá
běžně, přestala být pojistkou a stala se pravidlem** — a nikde to není
vidět, protože všechno dál funguje.

### Ještě jeden model, který lhal

Když jsem si po zavedení přeplácnutí procházel vlastní kód, ukázalo se,
že simulace **odečítala Power při každém průrazu**. Server ho ale
neodečítá — je kumulativní přes celý svět a nuluje se až dojetím kola
nebo přechodem jinam. Simulace tedy měřila jinou hru, než jaká poběží,
a celé ladění cen na ní stálo.

Po opravě vyšlo tempo o 70 % rychlejší a ceny světů se musely dopočítat
znovu. Je to dobrá připomínka toho, že model může být přesný a přitom
měřit něco jiného než skutečnost — a že nejužitečnější revize kódu je
ta, kterou si uděláš na vlastní práci z minulého kola.

## Zlaté pickupy

Malá část pickupů (asi 2 %) stojí **25×**. Je to jediný moment na trati,
který se nedá odhadnout dopředu — všechno ostatní je pravidelné, a hra,
ve které nikdy nic nepřekvapí, se přestane hrát.

Které to jsou, se **neposílá po síti**. Odvozuje se to čistě z čísel,
která obě strany stejně znají (svět, kolo, index pickupu), takže server
i klient dojdou k témuž bez jediného bajtu navíc — a hráč si sadu
nemůže vybrat.

Míchá se přes `bit32`, protože Luau operátor `~` nezná, a násobitele
jsou **šestnáctibitové**: Luau počítá v doublech, takže součin dvou
32bitových čísel přeteče přesnost (2^53) a spodní bity, na kterých
celý hash stojí, se tiše ztratí.

První verze jen provázala tři součiny přes XOR. Vypadalo to dobře a test
to shodil hned: v některých kombinacích světa a kola nevyšel **ani jeden**
zlatý pickup a v prvním světě seděly v pravidelném rozestupu. Málo
míchání se nepozná jinak než měřením — proto na to jsou tři testy
(vzácnost, rozestupy, změna mezi světy a koly).

## Nálet (surge)

Průraz a sbírání spolu do teď nesouvisely: zeď spadla, hráč běžel dál
a řetěz mu mezitím většinou stihl spadnout taky.

Průraz **s rozjetým řetězem** (40+ článků) teď na čtyři vteřiny zrychlí
běh o třetinu a zvětší dosah sbírání. Hráč se k dalším pickupům dostane
dřív, takže řetěz udrží — a vzniká smyčka, která dosud chyběla:

```
drž řetěz → proraž → nálet → řetěz vydrží → proraž…
```

**Proč combo a ne přeplácnutí:** nejdřív to viselo na přeplácnutí, jenže
to je skoro vždycky vysoké — hráč ke zdi dobíhá s přebytkem, ať dělá co
dělá. Nálet by běžel pořád a přestal by být odměnou. Simulace to ukázala
černé na bílém: `SURGE=97% barier`. Řetěz naproti tomu hráč buď drží,
nebo ne. To je skutečná dovednost, a tak se dnes spouští na 54 % zdí.

Čas vypršení drží server jen v paměti, ne v profilu — trvá pár vteřin,
takže by se do DataStore stejně nestihl propsat a jen by přidal zápisy.
Klient si ho hlídá taky, ale jen kvůli lište a kvůli tomu, aby po jeho
konci nepočítal s vyšší rychlostí, než jakou server dovolí.

## Rebirth: tokeny místo jednoho čísla

Rebirth byl dřív jedno číslo — zaplatíš, dostaneš +50 % ke všemu, jedeš
dál. Žádné rozhodnutí, a to zrovna u kroku, který tě stojí celý postup.

Teď je za každý rebirth **token** a osm větví, do kterých se dá utratit:

| Větev | Co dělá | Odemkne se |
|---|---|---|
| 🧠 Muscle Memory | rebirth ti nechá část úrovní | hned |
| 🌙 Night Shift | vyšší výdělek, když nehraješ | hned |
| 🐾 Pack Leader | +1 slot na peta | 1 rebirth |
| 🌊 Flow State | combo vydrží déle | 1 rebirth |
| 💥 Demolition | přeplácnutí platí víc | 2 rebirthy |
| 💎 Prospector | +1 gem za dokončené kolo | 3 rebirthy |
| 🍀 Four Leaf | +2 % šance na ×5 pickup | 4 rebirthy |
| ⭐ Compound | každý rebirth dá víc než dřív | 5 rebirthů |

Celý strom stojí víc tokenů, než kolik jich dostaneš za dobu, kdy se
odemyká — takže druhý rebirth vypadá jinak než první a dva hráči si
nejsou podobní.

Tokeny se **nikde neukládají**. Dostupné = rebirthy mínus to, co už je
v koupených úrovních. Nejde tak vyrobit stav, ve kterém profil tvrdí, že
tokeny má, ale nikdy za ně nezaplatil.

## Rozjetí ve Studiu

Projekt používá [Rojo](https://rojo.space) — kód žije v gitu a synchronizuje se
do Studia.

```bash
rokit install     # nainstaluje Rojo, StyLua, Selene
rojo serve
```

Ve Studiu nainstaluj Rojo plugin, dej **Connect** a strom se naskládá sám.
Pak Play — světy, tratě i UI vzniknou při startu serveru.

### Nechci nic instalovat, chci si to jen zahrát

```bash
tools/build.sh
```

Rojo si skript stáhne sám, projede kontroly a vyrobí `PowerSmash.rbxlx`.
Ten otevři ve Studiu a dej **Play** — žádný plugin, žádný toolchain.

Co na hře otestovat a podle čeho poznat, že je něco špatně, je
v [`docs/TESTOVANI.md`](docs/TESTOVANI.md).

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

### Hudba, která se nenahrávala

Přepínač **Music** v nastavení dlouho nedělal vůbec nic — byl v profilu,
byl v panelu, a nebyl na nic napojený. Teď zapíná procedurální podklad.

Nota je krátký vzorek přehraný ve správné výšce, melodie je seznam
stupňů pentatoniky. Bez půltónů se to nedá rozladit, takže i vzor,
který nikdo nesložil, zní jako hudba. Hrají dvě vrstvy proti sobě:

| Vrstva | Vzorek | Co dělá |
|---|---|---|
| **Bass** | `SWIM` staženě | pomalý spodek, drží tíhu |
| **Melody** | `STEP` vysoko | rychlejší svršek, dává pohyb |

Pomlky ve vzoru jsou důležitější než noty: bez nich je z toho drnčení,
s nimi to dýchá. Tempo se liší podle světa a **hlasitost roste s comboem**
— rozjetý řetěz je pak slyšet i v podkladu, ne jen v jednorázových zvucích.

Hudba má vlastní `SoundGroup`, ne Ambience: podklad se při každém průrazu
stahuje (ducking), a to je u dronu správně — u hudby by z toho bylo cukání
v rytmu, který s tím jejím nesouvisí.

Smyčka běží pořád, i s vypnutou hudbou; vypnutí jen stáhne hlasitost
skupiny. Zastavovat ji by znamenalo řešit, kde se má po zapnutí navázat,
a rytmus by se rozešel se světem.

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

## Vzhled

Paleta a rozvržení jsou odkoukané z největších her v žánru a spojené
s barevnými trendy 2026 (hyper-violet, acid green, crystalline blue,
retro pink na tmavém podkladu).

Celý vizuální jazyk stojí na pěti věcech. Když jedna chybí, UI okamžitě
vypadá jako prototyp:

1. **Dvojitý obrys** — tmavý vnější (4 px) a světlý vnitřní. Bez něj se
   prvky slévají s pozadím.
2. **Svislý gradient** na každé ploše, světlejší nahoře. Dělá „plast".
3. **Stud textura** — jemná mřížka teček na panelech. Ten rozpoznatelný
   Roblox „kostičkový" pocit. Kreslí se z malých `Frame` prvků, ne
   z obrázku, a počet je zastropovaný.
4. **Tlustý obrys písma** přes `UIStroke` v režimu `Contextual`. Vestavěný
   `TextStroke` je jednopixelový a v téhle paletě zmizí.
5. **Kulaté tučné písmo** (`FredokaOne`), obří čísla ještě tučnější
   (`LuckiestGuy`).

Tokeny jsou v `src/client/UI/Style.luau`, hotové komponenty (panel, karta,
chip pilulka, ikonová dlaždice, promo karta, lišta, obří číslo)
v `Widgets.luau`.

### Rozvržení HUDu

| Místo | Co tam je |
|---|---|
| vlevo nahoře | peníze a gemy jako chip pilulky se zeleným `+` |
| vlevo | mřížka ikon s popiskovou lištou pod ikonou |
| vpravo | promo sloupec s nabídkami za gemy |
| uprostřed | obří číslo Poweru a **rozpis násobičů v barvách** |
| dole | tan/zlatá lišta postupu s tečkami za jednotlivé zdi |
| úplně dole | rychlé nákupy tří klíčových vylepšení |

Rozpis násobičů není dekorace — v žánru je to hlavní důvod, proč si hráč
něco kupuje. Musí být vidět, odkud každý násobek přišel, a zdroj, který
zrovna nic nedělá, se schová.

## Testy: proč zelený build nestačil

Projekt měl několik kol v sobě chybu, kvůli které hra nemohla naběhnout —
osm remotů se používalo, ale nebylo definováno — a build byl celou dobu
zelený. **Kompilátor u dynamického jazyka kontroluje míň, než to vypadá:**
`Remotes.Neexistuje` se v pohodě zkompiluje a spadne až ve chvíli, kdy se
na to sáhne.

Testy proto stojí na třech úrovních, každá chytá něco jiného:

**1. Statická kontrola** (`tools/lint.py`) — ověřuje, že každý použitý
remote existuje v definicích a že `Modul.neco` na tom modulu opravdu je.
Běží nad zdrojáky, nespouští nic.

**2. Čistá logika** (`tests/Lock.spec.luau`, `Trade.spec.luau`,
`Throttle.spec.luau`) — zámek profilu, obchod a omezovač volání jsou
schválně oddělené do funkcí bez Roblox API, právě aby se daly otestovat.
Je to kód, kde chyba znamená ztracený postup nebo rozbitou ekonomiku,
a nedá se ověřit hraním: reprodukce potřebuje dva servery ve správný
okamžik.

**3. Start celé hry** (`tests/Boot.spec.luau`) — načte celý strom modulů
a **skutečně nastartuje server** proti náhradě Roblox prostředí
(`tests/support/roblox.luau`). Provede se tím veškerý kód, který běží při
startu: stavba světa, napojení remotů, nastartování služeb.

Ta náhrada prostředí není věrná simulace enginu — to by byla práce na
měsíce. Stačí, aby se kód provedl. Klíčové rozhodnutí je, že
**`task.wait` se nikdy nevrátí**: nekonečné smyčky (`while true do
task.wait(1) … end`) se tím provedou právě jednou až k prvnímu čekání
a odloží se. Chyba v prvním průchodu se najde, test neuvízne.

```bash
python3 tools/test.py    # 145 testů, z toho celý start hry i připojení hráče
python3 tools/lint.py
```

Každou z těch kontrol jsem ověřil tím, že jsem záměrně rozbil kód
a přesvědčil se, že selže. **Kontrola, která nemůže selhat, není
kontrola** — a v tomhle projektu na to došlo čtyřikrát.

Naposledy takhle: napsal jsem test, že cíl úkolu na combo nepřeleze
strop řetězu, jenže porovnával už oříznutou hodnotu — `math.min(x, M) <= M`
je pravda vždycky. Test procházel a číslo v `Live` bylo přitom nesmyslné.
Opravou bylo testovat **surové číslo z konfigurace**, ne výsledek ořezu.

## Ochrana proti zneužití

Každý remote je vstupní bod, přes který může klient poslat cokoliv.
Kromě kontroly typů a vlastnictví u každého z nich stojí obrana na dvou
věcech:

**Rate limiting.** `RemoteFunction` může klient volat tak rychle, jak
stihne, a několik handlerů zapisuje do DataStore — nákup vejce, denní
odměna, rebirth, obchod. Jeden hráč držící tlačítko by vyčerpal kvótu
zápisů pro celý server a ostatním by se přestalo ukládat. Limity jsou
proto velkorysé vůči člověku a přísné vůči skriptu:

| Skupina | Limit | Co tam patří |
|---|---|---|
| `Write` | 12 / 10 s | cokoliv, co může skončit zápisem do DataStore |
| `Cheap` | 40 / 10 s | čtení z paměti, nasazování, nastavení |
| `Social` | 8 / 10 s | pozvánky k obchodu a nabídky nákupu — proti obtěžování |

`Collect` a `Smash` mají vlastní, mnohem přísnější limit počítaný na
sekundu: chodí desetkrát častěji než cokoliv jiného.

**Statická kontrola.** Luau je dynamický, takže `Remotes.Neexistuje` se
v pohodě zkompiluje a spadne až za běhu. `tools/lint.py` proto ověřuje,
že každý použitý remote existuje v definicích. Není to teoretická
starost — v projektu se přesně tohle jednou stalo: osm remotů se
používalo, ale chybělo v definicích, a hra by vůbec nenaběhla. Kompilace
o tom mlčela.

```bash
python3 tools/lint.py
```

## Obchodování

Poslední velká funkce žánru — a zároveň nejčastější díra na duplikaci
itemů. Klasické způsoby, jak z obchodu vytáhnout věci zadarmo:

- nabídnout peta, kterého mezitím sloučíš nebo obchoduješ jinde,
- nabídnout desetkrát toho samého, kterého máš jednou,
- potvrdit, počkat, až potvrdí druhý, a **na poslední chvíli nabídku
  vyměnit** za bezcennou,
- odejít v půlce a doufat, že se výměna provede jen na jedné straně.

Proti tomu stojí čtyři pravidla:

1. **Jakákoliv změna nabídky ruší obě potvrzení.** Tím padá útok
   s výměnou na poslední chvíli.
2. **Vlastnictví se ověřuje znovu v okamžiku výměny**, ne při vkládání do
   nabídky. Mezitím mohl hráč peta sloučit.
3. **Obě strany se zapisují naráz** a teprve pak se ukládají. Kdyby se
   zapisovalo po jedné, mohla by jedna strana o pety přijít a druhá je
   nedostat.
4. **Pet daný pryč se sundá z nasazených** — jinak by se jeho bonus dál
   počítal, což je tichá varianta duplikace.

Obchod jede jen v rámci jednoho serveru. Přes servery by potřeboval
rozhodčího nad DataStore a otevřel celou třídu chyb, kde jedna strana
zapíše a druhá ne.

Veškerý výpočet je v `src/shared/Trade.luau` jako čisté funkce nad
obyčejnými tabulkami — a proto se dá otestovat. Nejdůležitější test
hlídá, že **výměna nezmění celkový počet kusů**: co zmizí jednomu, musí
přibýt druhému. Když se tahle vlastnost poruší, obchod buď itemy vyrábí,
nebo je ničí, a obojí zabije ekonomiku.

## Analytika: kde hráči odcházejí

Zlepšit se nedá to, co se neměří. Bez tohohle víš, že ti lidi odcházejí,
ale ne jestli **v prvních třiceti sekundách** (nepochopili ovládání),
**po první zdi** (nudné tempo), nebo **po první hodině** (došel obsah).
Každá z těch tří odpovědí znamená úplně jinou opravu.

Onboarding funnel je proto rozepsaný na kroky, které jdou po sobě
v první minutě: připojení → první pickup → první průraz → první upgrade
→ první pet → druhý svět. Kde se čísla mezi dvěma kroky propadnou, tam
je problém.

Dvě věci, na kterých to stojí:

- **Do funnelu patří jen noví hráči.** Kdyby se veteránovi počítalo
  „joined", vypadal by poměr kroku 1 → 2 mnohem hůř, než jaký u nováčků
  doopravdy je.
- **Selhání se hlásí.** Samotný `pcall` by schoval i chybu v podpisu
  volání a hra by tiše neposílala nic — což je horší než neměřit vůbec,
  protože to vypadá, že se měří.

Události jde posílat jen ze serveru a jen v publikované hře; ve Studiu
tiše nic nedělají.

## Ukládání: session locking

Nejčastější příčina ztráty postupu v Robloxu není chyba v ukládání, ale
**stejný profil běžící na dvou serverech naráz**. Oba si ho načtou, oba ho
uloží, a ten pomalejší přepíše novější data. Stačí, aby hráč rychle
přeskočil mezi servery.

Řešení je zámek zapsaný **ve stejném `UpdateAsync`** jako načtení: do klíče
se uloží JobId serveru a čas. Jiný server pak vidí, že je profil zabraný,
a nenačte ho. Během hraní se zámek obnovuje (každých 45 s), aby dlouhé
sezení nevypadalo jako mrtvé, a při odchodu se uvolní.

Když server spadne, zámek zůstane viset — proto má limit 150 sekund.
Po jeho vypršení ho další server může převzít.

Logika zámku je schválně ve vlastním modulu `src/shared/Lock.luau` jako
čisté funkce bez síťových volání. Je to nejchoulostivější kód v projektu
a nedá se ověřit hraním — aby se chyba projevila, musely by se dva servery
sejít ve správný okamžik. Proto má vlastní testy:

```bash
python3 tools/test.py
```

Testy pokrývají i hraniční případ, kvůli kterému to celé existuje: profil
uložený **před** zavedením zámku má data na nejvyšší úrovni. Kdyby se nový
tvar rozpoznával špatně, všichni stávající hráči by přišli o postup.

## Síť: co smí spadnout pod stůl

`PowerChanged`, `SmashEffect` a tik Obří zdi jezdí po
`UnreliableRemoteEvent`. Není rychlejší ani menší než běžný remote — je
**neprioritní**. Když se síť zahltí, zahodí se ona místo toho, aby zdržela
nákup nebo uložení profilu. Zahozený tik Poweru se za desetinu sekundy
nahradí novějším; zahozený nákup by hráče naštval.

Herní stav na tom nestojí: po průrazu jde reliable `ProfileChanged`, takže
se bariéra otevře i tehdy, když se efekt ztratí. `syncBarriers` je zároveň
záchranná síť — srovná i praskliny, které by jinak zůstaly viset.

## Mobil

Většina hráčů tohohle žánru sedí na telefonu — referenční screenshoty jsou
z mobilu. Pevné pixelové rozměry na monitoru vypadají dobře a na mobilu se
rozsypou, takže `src/client/UI/Layout.luau` řeší dvě věci naráz:

- **Škálování** podle výšky viewportu, ale s podlahou na 0,72. Pod ní by
  se tlačítka přestala dát trefit prstem.
- **Breakpoint** pod 900 px šířky: rozvržení se nemění velikostí, ale
  **tvarem** — dvousloupcová mřížka ikon se složí do jednoho sloupce
  a promo karty se zmenší. Zmenšit dvousloupcovou mřížku na polovinu
  nepomůže, když na ni pak nejde kliknout.

Okno panelů je relativní ke obrazovce se stropem i podlahou, takže se
vejde vždycky.

Detail, na kterém to skoro ztroskotalo: `UIScale` zmenšuje prvek kolem
jeho **vlastního** AnchorPointu. Na celoobrazovkovém kontejneru by se
všechno stáhlo k levému hornímu rohu a prvky ukotvené vpravo by skončily
uprostřed. Škáluje se proto každá ukotvená skupina zvlášť.

## Obří zeď

Serverová událost. Uprostřed hubu stojí zeď se **společným životem pro
celý server** — a přispívá se do ní běžnými průrazy, takže hráč nemusí
nikam chodit ani nic přepínat.

Odměna se dělí podle podílu na poškození, ale základ dostane každý, kdo
přispěl aspoň něčím. Čistý podíl by odřízl nováčky, rovný díl by odměnil
přihlížení. Po proražení dostane celý server ×2 boost na tři minuty.

Život zdi se počítá z nejsilnějšího hráče na serveru, ne z pevného čísla:
server samých začátečníků by na pevnou hodnotu nedosáhl, server veteránů
by ji smetl za pár vteřin.

## Technická vrstva

Čtyři věci, které dělají rozdíl mezi „efekt se přehrál" a „něco se stalo".

### Zvuk: jeden vzorek, šest materiálů

Roblox má hotové DSP instance (`ReverbSoundEffect`, `EqualizerSoundEffect`,
`DistortionSoundEffect`, `ChorusSoundEffect`, `FlangeSoundEffect`,
`TremoloSoundEffect`, `PitchShiftSoundEffect`, `CompressorSoundEffect`)
a dají se pověsit na `SoundGroup`. Tím se z hrstky vestavěných vzorků dá
udělat cokoliv — nemění se vzorek, mění se to, co se s ním stane po cestě:

| Svět | Řetězec |
|---|---|
| Sklo | ostré výšky, uříznuté basy, krátký jasný dozvuk |
| Želé | dolní propust, chorus, mokrý dozvuk |
| Led | skelné výšky, flanger, dlouhá stopa |
| Čokoláda | samé basy, tvrdá komprese, zkreslení |
| Neon | tremolo dělá blikání, hodně dozvuku |
| Void | dozvuk 12 s, posun o oktávu dolů |

Profily jsou v `Assets.Dsp`, řetězec staví `SoundKit`. Při změně světa se
hodnoty **dojedou**, ne přepnou — proto se efekty nemažou, jen stahují na nulu.

Tři skupiny místo jedné: **Material** (jde přes DSP), **Ui** (bez efektů —
dozvuk na kliknutí zní jako chyba) a **Ambience** (podklad, aby se dal při
průrazu stáhnout). To stažení je **ducking**: náraz dostane prostor a zní
tvrději, aniž by se musel zesilovat.

Ambientní podklad není hudba — je to jeden vzorek stažený na 18 % rychlosti
a puštěný ve smyčce přes ten samý dozvuk jako zbytek světa.

### Fyzika: bariéra se láme, ne rozpadá

`Fracture.luau` dělá dvě věci jinak než náhodné střepy:

1. **Láme podle mřížky** — buňky s náhodným posunem drží tvar původní desky,
   takže je poznat, odkud který kus byl.
2. **Impuls z místa nárazu** — každý kus dostane směr od bodu, kde do desky
   hráč vrazil, sílu podle vzdálenosti a k tomu část hráčovy rychlosti.
   Průraz v běhu proto vypadá jinak než průraz z místa.

Kusy padají na zem, dokutálí se a teprve pak vyblednou. Kolizní skupina
`Debris` (registruje ji server) je drží stranou od hráče — jinak by ho
vlastní destrukce házela po chodbě. Díly se recyklují z poolu.

Rázová vlna navíc projde okolní neukotvené díly a přidá jim rychlost,
takže dosáhne i na střepy z předchozích průrazů.

### Kamera na pružinách

Lineární doběh vypadá mechanicky. Skutečná kamera má hmotnost, takže
`CameraFX` používá tlumenou pružinu:

```
zrychlení = -tuhost * výchylka - tlumení * rychlost
```

Otřes má nízké tlumení (má se rozdrnčet), zorné pole vysoké (kmitající FOV
je nepříjemný). Náklon jde na tu stranu, ze které hráč do desky vjel.
Záblesk nezakrývá obraz bílým obdélníkem — zvedne jas a bloom, takže se
rozzáří to, co už na obrazovce svítí.

### Pickupy, které letí

Pickup, který na dotek zmizí, se nedá cítit. Tenhle vystřelí k hráči
se zrychlením (`progress²`, ne konstantní rychlost) a praskne až u něj.
Je to nejmenší úprava s největším dopadem na pocit ze hry.

K tomu **praskliny**: bariéra jich dostává víc podle toho, jak je nabitá,
takže postup je vidět i bez koukání na lištu.

### Proč se textury negenerují v kódu

Roblox to umí (`AssetService:CreateEditableImage`), ale **v publikovaných
hrách je to ve výchozím stavu vypnuté** a vyžaduje ověření věku i identity
tvůrce. Většina hráčů by textury nikdy neviděla. Vzhled proto stojí na
geometrii, `Beam`ech a částicích, které fungují vždycky.

## Textury a pohyb

Žádná textura se nenahrává, a přesto se všechno hýbe:

| Efekt | Jak je udělaný |
|---|---|
| Energetické pole na bariéře | Svislé `Beam`y s `TextureSpeed` — Beam bez obrázku je plný barevný pruh, takže proudí i bez assetu |
| Pulzování bariéry | Barva dýchá tím rychleji, čím blíž je proražení — postup vidíš, i když se nedíváš na UI |
| Tekoucí pruhy na podlaze | Neonové díly, které se posouvají k bariéře a ukazují, kam běžet |
| Posouvající se textury | `OffsetStudsU/V` — klasická technika na tekoucí energii. Zapne se sama, jakmile do `Assets.Textures` doplníš vlastní obrázek |
| Buněčná mřížka na tabuli | `SurfaceGui` s mřížkou `Frame` prvků — skutečná textura bez obrázku. Plní se zdola podle nabití, takže postup je vidět na zdi samotné |
| Rozjetá trať | Combo zrychlí tok pruhů i posun textur a zjasní pruhy — čím vyšší stupeň, tím rozjetější svět kolem tebe |

Zrychlení se **dojíždí**, neskáče: cíl a aktuální hodnota se drží zvlášť
a sbíhají se exponenciálně. Skok na plný tok v jednom snímku vypadá jako
závada, doběh za desetinu vteřiny jako zrychlení. Pruhy si přitom pamatují
ujetou vzdálenost místo toho, aby se počítaly z `elapsed * rychlost` —
jinak by se při změně tempa skokem přemístily.

### Terén se mění pod nohama

Do teď měl celý svět jeden materiál a jednu barvu. Hráč proběhl dvanáct
zdí a pod nohama měl pořád totéž — postup byl jen v číslech, ne v tom,
co vidí a slyší.

Trať je proto rozdělená na **šest zón po dvou zdech**:

| Zóna | Od zdi | Lesk | Zvuk | Mačká se |
|---|---|---|---|---|
| Jelly Flats | 1 | 0,10 | mokré stlačení | 1,00 |
| Marshmallow | 3 | 0,15 | tlumené žuchnutí | 0,85 |
| Butter Block | 5 | 0,22 | lepkavé odtržení | 0,60 |
| Sugar Glass | 7 | 0,45 | křupnutí | 0,20 |
| Chrome Mile | 9 | 0,85 | kovový úder | 0,00 |
| Void Edge | 11 | 0,55 | nasáté ticho | 0,00 |

Jdou od nejměkčí k nejtvrdší, a to ve **všech třech rovinách naráz** —
lesk, zvuk i to, jak moc se pod tebou promáčknou. Když jde všechno jedním směrem, hráč pozná postup
i se zavřenýma očima; kdyby si roviny odporovaly (měkký zvuk na kovu),
působilo by to jako chyba, ne jako styl.

Zeď nese materiál **zóny**, ne světa, takže hráč neproráží dvanáctkrát
to samé. Barva zůstává světu, aby bylo pořád poznat, kde jsi.

Na začátku každé zóny stojí cedule s jménem — bez ní by se terén změnil
„jen tak" a nebylo by to poznat jako milník.

**Zvuk se mění s ním** — a každá zóna má vlastní recept, ne jen jinou
výšku téhož vzorku. Tak by vznikl „stejný zvuk, jen vyšší", ne jiný
materiál. Rozdíl dělá kombinace tří věcí:

1. **z čeho** — mokrý vzorek (`impact_water`, `swim`) proti suchému
   (`footsteps`, `jump_land`)
2. **kolik vrstev a jak posunutých** — jedna vrstva je ťuknutí, tři těsně
   za sebou jsou křupnutí
3. **ohyb výšky** — a tohle je to jediné, co dělá *squishy*

### Ohyb výšky

Krátký vzorek s pevnou výškou zní jako ťuknutí, ať ho ekvalizérem ohneš
jakkoliv. Ten samý vzorek, který během desetiny sekundy **sjede o oktávu
dolů**, zní jako mokré stlačení — protože přesně to dělá měkký materiál
fyzicky: jak se hmota stlačuje, klesá její rezonanční frekvence.

Nahoru to funguje stejně: sklouznutí vzhůru zní jako odskok. Karamel
proto sjede dolů a hned zpátky nahoru — lepkavé odtržení.

```lua
Jelly = {
    Step = {
        { Id = SPLASH, Pitch = 0.75, Volume = 0.3, Bend = 0.42, BendTime = 0.16 },
        { Id = SWIM,   Pitch = 0.9,  Volume = 0.18, Delay = 0.02, Bend = 0.55, BendTime = 0.2 },
    },
}
```

Jede se to tweenem, ne po snímcích: tween běží na straně enginu, takže
deset vrstev naráz nestojí nic navíc a nerozejde se s hudbou, když
klientu klesne snímková frekvence.

**Průraz zní ze dvou receptů naráz** — světa (sklo, čokoláda, neon)
a zóny, ve které zeď stojí. Svět dá zvuku barvu, zóna hmotu: tatáž
skleněná zeď proto v marshmallow žuchne a v chromu zazvoní.

Zóna se určuje z **indexu bariéry**, ne z pozice: server podle indexu
ověřuje průraz, takže z něj musí vycházet i všechno ostatní. Jinak by
hráč mohl stát na jednom terénu a slyšet jiný.

## Squishy: pomalý návrat

Celý půvab squishy hraček stojí na jedné věci: **zmáčkneš je a ony se
vrátí pomalu**. Ne odpruží — pomalu se zvednou. Důlek po prstu zůstane
vidět ještě vteřinu poté, co jsi ruku dal pryč, a to je přesně to, co je
na tom uspokojivé.

Ve hře to dlouho nebylo. Pickup zmizel, zeď se buď prorazila, nebo se
nestalo nic. Nic nereagovalo na dotek a nic si dotek nepamatovalo.

`src/client/Squish.luau` je ta chybějící vrstva. Umí jediné: promáčknout
díl a nechat ho pomalu vrátit. Křivka je schválně `t^2.2`:

| Křivka | Jak to vypadá |
|---|---|
| lineární | jako výtah, mechanicky |
| ease-out | vystřelí zpátky — to je guma, ne squishy |
| **`t^2.2`** | chvíli zůstane dole a teprve pak se zvedne |

Právě to zdržení na dně je ten „slow rise", kvůli kterému lidi ta videa
sledují. Hlídá to test: v polovině času musí být důlek pořád z větší
části dole.

Dvě věci, které to dělají stlačením a ne zmenšením:

- **Hmota se nikam neztratí** — co ubude v hloubce, přibude do stran.
  Bez toho vypadá zmáčknutí jako zmenšení.
- **Střed se posune** o polovinu toho, co ubylo, ve směru mačkání —
  protilehlá strana tím zůstane přesně tam, kde byla. Pickup se proto
  promáčkne shora a nepropadne se do země.

### Kde se to používá

**Zeď.** Zeď je jeden díl a díl se lokálně promáčknout nedá. Na její čelo
se proto pověsí mřížka tenkých bloků — a ty už se mačkat dají, každý
zvlášť. Když do zdi vrazíš, propadnou se ty kolem tebe a pomalu se
vrátí. Hloubka klesá se vzdáleností od nárazu, takže vznikne **důlek**,
ne rovnoměrné stlačení celé zdi.

Mřížka se staví jen pro tu jednu zeď, kterou hráč zrovna vidí. Dvanáct
naráz by bylo tři sta dílů za něco, co stejně není vidět.

**Pickupy.** Po sebrání se vrátí **zmáčknuté** a pomalu se nafouknou.
Sedne to i časově: doba návratu je respawn pickupu.

### Materiály

Vzhled je odkoukaný ze squishy hraček: krémové pastely, hladký povrch,
jemný lesk. Máslo, mochi, jahoda. Proto je skoro všude `SmoothPlastic`
s malou odrazivostí — je to jediný materiál v Robloxu, který vypadá jako
měkký vinyl. Drsné materiály (`Mud`, `Sand`, `Slate`) tenhle dojem
zabíjejí, i když tematicky „sedí".

### Jedna obří zeď

V dohledu je vždycky **jen jedna zeď** — ta tvoje. Přes celou chodbu,
od podlahy až ke stropu oblouku.

Dřív jich stálo dvanáct za sebou a byla to tabule uprostřed průchodu:
vypadala jako dveře, kolem kterých se dá projít, a hráč viděl celou trať
dopředu, takže nebylo co objevovat. Zeď, kterou nejde obejít ani
přeskočit, je jediné, co dá průrazu váhu.

Další zdi zůstávají postavené, ale neviditelné. Kolizi si drží — server
by hráči průchod dál stejně neuznal a jen by ho to zmátlo.

### Jak trať vypadá

Chodba z podlahy a dvou zdí je technicky správně a vypadá jako krabice.
Rozdíl mezi „prototyp" a „hra" dělá to, že prostor má **rytmus** — něco,
co se opakuje a čím kolem tebe ubíhá, takže je vidět rychlost.

Trať proto stojí na třech vrstvách v různých vzdálenostech:

| Vrstva | Co dělá |
|---|---|
| **Oblouky** u každé bariéry | rámují cíl, na který běžíš, a zvedají strop |
| **Sloupy** mezi bariérami | míjíš je nejblíž, takže dělají pocit rychlosti |
| **Plovoucí kry** za stěnami | hloubka pozadí — bez nich končí svět tři metry od tebe |

K tomu **příčné prahy v podlaze** každých 20 studů, každý čtvrtý výraznější.
Jednolitá plocha rychlost neukáže, protože oko nemá čeho se chytit.

Velikosti a natočení ker se odvozují z indexu, ne z náhody — svět tak
vypadá na každém serveru stejně a jde reprodukovat.

Světla jsou to nejdražší, co se dá do světa dát, takže je má jen oblouk
(24 na svět); hlavice sloupů svítí samotným `Neon` materiálem. V nízké
grafice klient všechna světla ve světě zhasne — postavil je server, ale
zhasnout je může kdokoliv.

To celé je **208 dílů na svět**. Se `StreamingEnabled` se načítá jen ten,
ve kterém zrovna stojíš.

### Šťáva

Věci, které nejsou vidět v kódu, ale jsou cítit při hraní:

- **Hitstop** — při průrazu se hráč na pár setin sekundy nehne. Engine
  pozastavit nejde a ani nemusí: co dělá náraz hmotným je právě to
  zaseknutí. Ošetřené jsou dva případy, ve kterých by postava zůstala
  stát: dva průrazy hned po sobě (generace) a respawn během zaseknutí
  (rychlost se obnovuje na tu, kterou povolil server, ne na zapamatovanou).
- **Dojezd kola** — poslední tři zdi mají silnější otřes, záblesk i text
  (`2 TO GO`, `LAP COMPLETE!`). Dvanáctý stejný průraz v řadě není dojezd.
- **Přeplácnutí se ukazuje** až od ×1,5. Psát „×1.1" u každé zdi by z toho
  udělalo šum, ze kterého se nedá nic vyčíst — a hráč se právě tohle má
  naučit.
- **Jiskry u pickupů** houstnou s comboem, takže je rychlost vidět i dole
  u nohou, ne jen na kartě v rohu.

### Pohyby postavy

Taky celé kódem, protože nahraná animace by znamenala cizí `rbxassetid://`:

- **náklon při běhu** — otočení `RootJoint.C0`
- **náklon do zatáčky** — počítá se ze změny směru rychlosti, ne ze
  vstupu: klávesy klient nezná (na mobilu jsou to gesta), rychlost ano.
  Svislá složka se zahazuje, jinak by skok vypadal jako prudké zatočení.
- **běžecký cyklus** — fáze roste s **ujetou vzdáleností**, ne s časem,
  takže při zpomalení kroky zpomalí spolu s postavou místo aby běžely
  dál na místě. Amplituda roste s rychlostí: chůze má paže skoro u těla,
  sprint jimi mává naplno.
- **houpání kamery** — `Humanoid.CameraOffset`
- **nabíjecí póza** — ramena dozadu, když máš dost Poweru na průraz
- **odraz při průrazu** — ruce dopředu, postava se protáhne, u nohou vyletí prstenec
- **dřep při dopadu** — krátké smáčknutí přes `BodyHeightScale`
- **prach při dopadu** — emitor visí na dočasném dílu, ne na noze: jinak
  by odletěl s postavou a prach by se táhl za hráčem místo aby zůstal ležet
- **rychlostní čáry a stopa** — zapnou se samy při vysoké rychlosti, barví se podle světa

Klíčový detail: pózy jdou přes **`Motor6D.C0`**, ne `Transform`. `Transform`
každý snímek přepíše Animator, takže by se pózy okamžitě smazaly. `C0` je
základní posun kloubu, který se s běžící animací sčítá — pózy se tak na
výchozí animaci navrství, místo aby s ní bojovaly.

## Obchod

Tři věci za herní měnu, žádná z nich neblokuje postup:

- **Denní nabídka** — jeden boost se 40% slevou, stejný pro celý server.
  Odvozuje se z čísla dne, takže není co ukládat a dva hráči vedle sebe
  vidí totéž. Sleva je schválně na boostech, ne na vylepšeních: vylepšení
  jsou trvalá a sleva na nich by rozhodila ekonomiku napořád.
- **Směna gemů** — 10 💎 za mince v hodnotě 15 minut tvého příjmu.
  Kurz je násobek příjmu, ne pevná částka: pevné číslo by bylo po hodině
  hraní směšné a pro nového hráče nedosažitelné.
- **Boosty** se při koupi za běhu **prodlužují**, nezahazují zbytek.

Cenu bere server ze svého času, ne z toho, co pošle klient — jinak by
si šlo „vybrat" den, kdy je boost v akci.

## Struktura

```
src/
  shared/          → ReplicatedStorage.Shared (vidí server i klient)
    Config.luau      pravidla hry — čísla, která se skoro nemění
    Live.luau        obsah, který měníš každý týden: kódy, denní odměny,
                     úkoly, pety, vejce, gamepassy, badge
    Track.luau       geometrie tratě spočítaná, ne postavená
    Economy.luau     vzorce progrese (jeden zdroj pro server i UI)
    Assets.luau      zvukové recepty a textury (viz kapitola Zvuky)
    Remotes.luau     definice síťové komunikace
    Format.luau      zkracování čísel (12.4K / 3.1M)
    Lock.luau        logika zámku profilu (čisté funkce, testované)
    Trade.luau       logika obchodu (čisté funkce, testované)
    Throttle.luau    omezovač volání (čisté funkce, testované)
    Build.luau       pomocníky pro díly a UI
  server/          → ServerScriptService.Server
    Services/
      DataService.luau    DataStore, autosave, odolnost proti výpadku
      WorldService.luau   postaví tratě všech světů
      GameService.luau    sbírání, validace průrazů, Power, auto-collect
      ShopService.luau    vylepšení, světy, boosty, tituly, rebirth, truhla
      PlayerService.luau  cedulka s titulem, leaderstats, offline výdělky
      RetentionService.luau denní odměny, úkoly, kódy
      EventService.luau     Obří zeď — serverová událost
      TradeService.luau     obchod mezi hráči (stavový automat)
      AnalyticsService.luau onboarding funnel a ekonomické události
      GuardService.luau     rate limiting nasazený na remote handlery
      PetService.luau       vejce, líhnutí, nasazení petů
      LeaderboardService.luau žebříček přes OrderedDataStore + tabule
      MonetizationService.luau gamepassy, produkty, badge
  client/          → StarterPlayer.StarterPlayerScripts.Client
    TrackView.luau   lokální pickupy a bariéry + hlavní herní smyčka
    Effects.luau     střepy, částice, rázová vlna, otřes kamery
    SoundKit.luau    vrstvený přehrávač + stoupající stupnice
    Textures.luau    energetické pole, tekoucí pruhy, pulzování
    CharacterFX.luau procedurální pohyby postavy
    UI/Layout.luau   škálování a breakpointy pro mobil
    UI/Preview.luau  3D náhledy petů přes ViewportFrame
    CameraFX.luau    kamera na pružinách, záblesky, úder do FOV
    Fracture.luau    lámání bariéry na kusy s impulsem z místa nárazu
    Pets.luau        pety létající za hráčem (pružinový pohyb)
    Onboarding.luau  nápověda pro první sezení
    UI/              HUD, panely, notifikace, widgety
  loading/         → ReplicatedFirst (loading screen s tipy)
tests/
  support/roblox.luau  náhrada Roblox prostředí pro testy
  Boot.spec.luau   start celé hry (načtení modulů + nastartování serveru)
  Lock.spec.luau   testy zámku profilu
  Trade.spec.luau  testy obchodu (hlavně proti duplikaci)
  Throttle.spec.luau testy omezovače volání
tools/
  simulate.py      simulace ekonomiky (viz níž)
  test.py          spouštěč testů (běží mimo Roblox)
  lint.py          statická kontrola remotů a importů
docs/
  LAUNCH.md        co udělat před vydáním a jak se dneska trenduje
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
| Daily & questy | — | tlačítko vlevo |
| Pety | — | tlačítko vlevo |
| Kódy | — | tlačítko vlevo |
| Worlds | `2` | tlačítko vlevo |
| Titles | `3` | tlačítko vlevo |
| Style (stopy, aury, skiny) | — | tlačítko vlevo |
| Rebirth | `4` | tlačítko vlevo |
| Zavřít panel | `Esc` | ✕ |

## Kosmetika

Stopy, aury a skiny v záložce **Style**. Nic se za ně neplatí — každý kus je vázaný
na statistiku, kterou hráč stejně sbírá (průrazy, rebirthy, odemčené světy,
vylíhlá vejce, odehraný čas).

Odemčení se **nikde neukládá**. Počítá se pokaždé znovu z profilu, takže
není co duplikovat, co ztratit při rollbacku ani co podvrhnout — v profilu
leží jen dvě id: co má hráč nasazené. Server nárok ověřuje při každém
nasazení, ne jen při kliknutí v panelu.

Vzhled je popsaný čísly, ne assety: rozdíl mezi stopami dělá barevný přechod,
šířka, doba dohasínání a svit; aury jsou jinak nastavené emitory. Žádné
`rbxassetid://`, které by v cizí hře nemuselo projít právy.

Dvě věci se hýbou za běhu — stopa s `Cycle` posouvá barvy po pásu, aura
s `Orbit` obíhá emitorem kolem těla. Nízká grafika obojí vypne: deset emitorů
kolem deseti hráčů je na slabém telefonu to první, co sundá snímkovou frekvenci.

Replikace jde přes atributy na `Player` (`CosmeticTrail`, `CosmeticAura`),
ne přes remote — atribut se dostane i k tomu, kdo se připojí později.

## Ladění ekonomiky

Ceny světů a rebirthu **nejsou odhad** — dopočítala je simulace na tyhle časy
aktivního hraní:

| Milník | Čas |
|---|---|
| Jelly Cave | 12,2 min |
| Ice Vault | 48,0 min |
| Chocolate Factory | 2,2 h |
| Neon Core | 5,2 h |
| Void Prism | 12,3 h |
| 1. rebirth | 0,9 h |
| 5. rebirth | 3,3 h |

Ceny světů dopočítal autoladič binárním hledáním na tyhle cíle — po
zavedení comba, kol a přeplácenutí se příjem změnil o řád a ručně
odhadnout by je nešlo.

Po každé změně čísel v `Config.luau` si to ověř:

```bash
python3 tools/simulate.py                        # kdy se odemknou světy
python3 tools/simulate.py --rebirth              # smyčka rebirthů
python3 tools/simulate.py --hours 6              # kratší běh
python3 tools/simulate.py --min-worlds 6         # selže, když je svět nedosažitelný
```

Poslední varianta běží i v CI. Změna čísel v `Config` nebo `Live` se
vždycky zkompiluje, ale klidně může rozbít tempo hry tak, že se to pozná
až po vydání.

Skript pouští **skutečné moduly hry** (`Config`, `Track`, `Economy`) mimo
Roblox, takže neměří kopii vzorců, ale to, co opravdu poběží. Potřebuje
binárku [`luau`](https://github.com/luau-lang/luau/releases) v PATH nebo
v `tools/`.

### Na co si dát pozor

- **StreamingEnabled je zapnutý** (`default.project.json`). Klient tak
  nedrží v paměti šest chodeb naráz. Režim `MinimumRadiusPause` klienta
  pozastaví, kdyby se dostal za načtenou oblast — bez něj by hráč po
  přesunu do dalšího světa propadl podlahou, která se ještě nenačetla.
  Když budeš na klientu sahat na díly ve `Workspace` podle jména, počítej
  s tím, že tam nemusí být.
- **Simulace kupuje i pety.** Bez toho by ignorovala systém, který
  násobí Power ze všech nejvíc. První verze modelu kupovala vejce při
  každé příležitosti a hráč se pak nikdy nedostal ze druhého světa —
  což nebyla chyba hry, ale chyba modelu chování.
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
- [x] Design systém podle žánrových referencí (stud textura, dvojitý obrys,
      chip pilulky, promo karty, rozpis násobičů)
- [x] Denní odměny se sérií a tři denní úkoly s vlastní sérií
- [x] Kódy, pety z vajec, žebříček přes OrderedDataStore
- [x] Gamepassy a produkty přes MarketplaceService (idempotentní ProcessReceipt)
- [x] Badge za milníky, nastavení, loading screen, nápověda pro nováčky
- [x] DSP řetězec podle světa — šest materiálů z jedné sady vzorků
- [x] Lámání bariéry podle mřížky s impulsem z místa nárazu a kolizními skupinami
- [x] Kamera na tlumených pružinách, ducking zvuku, magnetické pickupy
- [x] Responzivní UI pro mobil se skládacím rozvržením
- [x] Obří zeď — serverová událost se společným cílem a odměnou pro všechny
- [x] Slučování petů (3 stejné → silnější varianta, až tři úrovně)
- [x] CI: kompilace všech modulů, testy a kontrola ekonomiky na každý push
- [x] Session locking — profil nejde načíst na dvou serverech naráz
- [x] Nespolehlivé remoty pro časté zprávy, aby neucpávaly ty důležité
- [x] 3D náhledy petů v UI přes ViewportFrame
- [x] StreamingEnabled — klient nedrží v paměti světy, do kterých se nedívá
- [x] Obchodování mezi hráči s ochranou proti duplikaci a 15 testy
- [x] Analytika: onboarding funnel, pohyby měny, postup světy
- [x] Rate limiting na všech remote handlerech (36 testů celkem)
- [x] Statická kontrola, která chytí nedefinovaný remote před spuštěním
- [x] Náhrada Roblox prostředí — hru jde nastartovat a otestovat mimo Studio
- [x] 68 testů ve třech úrovních: statika, čistá logika, start celé hry

### Kam dál

- Vlastní ASMR nahrávky přes `Assets.Override` — hra zní i bez nich,
  ale vlastní samply jsou pořád největší skok v kvalitě
- Doplnit ID gamepassů, produktů a badge v `Live.luau` (viz `docs/LAUNCH.md`)
- Sezónní událost s vlastním světem a limitovanými pety
- Kosmetika: skiny bariér, efekty průrazu, stopy

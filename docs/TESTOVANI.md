# Jak hru otestovat

Cíl téhle stránky není „proklikat menu". Je to seznam věcí, které **jdou
rozbít, aniž by o tom kompilátor nebo testy věděly** — kamera, zvuk,
kolize, síťování, pocit ze hry. Přesně to, co v CI zjistit nejde.

U každého bodu je napsané **konkrétní číslo nebo chování**, takže se dá
poznat rozdíl mezi „funguje" a „vypadá, že funguje".

---

## 1. Rozjetí

Dvě cesty, obě fungují:

**A) Hotový soubor (nejrychlejší)**
Otevři `PowerSmash.rbxlx` ve Studiu a dej **Play**. Nic se neinstaluje.

**B) Rojo (když chceš upravovat kód)**
```bash
rokit install
rojo serve
```
Ve Studiu nainstaluj Rojo plugin → **Connect** → **Play**.
Výhoda: uložený soubor se do Studia propíše okamžitě.

### Než klikneš na Play
**Game Settings → Security → Enable Studio Access to API Services: ZAPNOUT.**
Bez toho nefunguje ukládání. Hra to pozná a napíše ti to žlutým toastem —
což je samo o sobě první věc k otestování.

### Co má být vidět hned
- V **Output** řádek `[Power Smash] Server běží — 6 světů postaveno.`
- Načítací obrazovka s tipy, pak zmizí
- Nápověda: *„Walk over the glowing +1 cubes to build POWER"*
- **Žádná červená chyba v Output.** Jedna červená chyba = konec testu,
  pošli mi ji.

---

## 2. Základní smyčka (2 minuty)

| Krok | Co má nastat | Když ne, je to |
|---|---|---|
| Projdi přes `+1` kostku | Zvuk stoupne o tón, číslo Poweru naskočí | rozbité sbírání |
| Sbírej 8 kostek | První zeď (`8 POWER`) je nabitá | špatný požadavek |
| Doběhni do zdi | Rozsype se na kusy, kamera trhne, +14 mincí | rozbitý průraz |

**Zeď Power spotřebuje.** Po průrazu ti zůstane jen přebytek — když ti
zůstane všechno, je to chyba.

**Zeď musí být obří** — přes celou chodbu, od podlahy až ke stropu
oblouku. A v dohledu smí být **jen jedna**: když vidíš řadu zdí až do
dálky, je to chyba.
| Zkus zeď, na kterou nemáš | Nepustí tě, tupý zvuk | chybí blokování |

První zeď stojí **8 Poweru** a platí **14 mincí**. Dvanáctá zeď stojí
**378 Poweru**. Když ti čísla nesedí, něco přepisuje `Config`.

---

## 3. Combo — nejdůležitější věc k otestování

Combo je nová mechanika a **nedá se otestovat jinak než hraním.**

1. Sbírej kostky **bez zastavení**
2. Po 8 článcích: vpravo naskočí karta **NICE**, ozve se tón, kamera se
   rozšíří
3. Pokračuj → **HOT** (25), **BLAZING** (50), **UNREAL** (80), **SMASHER** (100)
4. **Zastav se na 3 vteřiny** → karta zmizí, záběr se vrátí

Co hlídat:
- Lišta pod číslem **plynule ubývá**, netrhá se
- Na stropu karta ukazuje **×2.00 per pickup**
- Pruhy na podlaze při vyšším stupni **tečou rychleji a zjasní se**
- Zvuk hraje **jen při přeskočení stupně**, ne u každé kostky

> Kdyby řetěz rostl i když stojíš, počítá ho klient místo serveru — to je
> chyba, kterou hlas nahlas.

---

## 2b. Zlaté pickupy

Asi **2 %** pickupů je zlatých a stojí **25×**. Poznáš je i z dálky:
jsou větší, zlaté a mají nad sebou světelný sloupec.

- Rozeběhni se tratí a hledej sloupec — musí být vidět **přes** ostatní pickupy
- Sebrání dá zlatý záblesk obrazovky a toast `GOLDEN ×25!`
- **Po dojetí kola musí být jinde** — které jsou zlaté, se odvozuje ze
  světa a kola

> Které pickupy jsou zlaté, se po síti neposílá; server i klient to
> počítají ze stejného vzorce. Kdyby ti klient ukázal zlatý pickup a
> server ho neuznal (dostal bys jen +1), je to chyba — nahlas ji.

## 3b. Nálet (surge) — co na combo navazuje

Nálet je odměna za **udržený řetěz**, ne za silný průraz.

1. Vybuduj řetěz aspoň **40 článků** (karta ukazuje HOT nebo výš)
2. **S rozjetým řetězem** proraž zeď
3. Vpravo pod combem naskočí zelená karta **⚡ SURGE** s ubývající lištou
4. Na **4 vteřiny** běžíš o třetinu rychleji a sbíráš z větší dálky

Co hlídat:
- Když prorazíš zeď **bez řetězu**, nálet se objevit **nesmí**
- Po vypršení se rychlost musí vrátit na normál — když zůstaneš rychlý,
  je to chyba, nahlas ji
- Když si během náletu koupíš Speed upgrade, nesmí tě to zpomalit zpátky

> Tohle je ta smyčka, na které hra stojí:
> **drž řetěz → proraž → nálet → řetěz vydrží → proraž**

## 4. Přeplácnutí (overkill)

Tohle je ta oprava, kvůli které Power vůbec k něčemu je.

1. Nasbírej **hodně přes** požadavek zdi (třeba 60 Poweru na zeď za 8)
2. Prorazit → výplata musí být **znatelně vyšší** než těch základních 14

Porovnej dva průrazy: jeden hned po nabití, druhý s velkým přebytkem.
Když dají stejně, přeplácnutí se nepočítá.

---

## 4a. Terén a zvuk po zónách

Tohle je nejlepší způsob, jak poznat, že se hraje dobře: **dívej se pod
nohy a poslouchej**.

1. Rozeběhni se od startu a proraž pár zdí
2. **Poslouchej kroky.** V Jelly Flats musí být slyšet mokré stlačení —
   tón během kroku **sjede dolů**. To je ten squishy zvuk.
3. U zdi 3 marshmallow (tlumené žuchnutí), 5 karamel (lepkavé odtržení:
   tón sjede dolů a hned zpátky nahoru), 7 sklo (křupnutí), 9 chrom
   (kovový úder), 11 void (nasáté ticho)
4. Podlaha se musí měnit s tím: Mud → Snow → Sand → Glass → DiamondPlate
   → Glacier
5. **Zeď mění materiál taky** — ve voidu je to silové pole
6. Na začátku každé zóny stojí u kraje **cedule** s jejím jménem
7. V HUD vpravo se mění řádek `SUGAR GLASS · zone 4/6` i jeho barva

Šest zón po dvou zdech, od nejměkčí k nejtvrdší.

> Když se změní barva, ale ne zvuk (nebo naopak), je to chyba — obojí
> jede z jednoho místa a má se měnit spolu.

## 4c. Squishy — ta nejdůležitější věc

Celý pocit stojí na **pomalém návratu**: zmáčkneš a ono se to vrací pomalu.

0. **Rozhlédni se kolem trati.** Každý svět má vlastní rekvizity —
   krystaly, laloky, rampouchy, kádě s potrubím, svítící prstence,
   monolity. Některé se vznášejí a otáčejí. Nic z toho ti nesmí stát
   v cestě.
0. **Koukej na vzor podlahy.** Každá zóna má jinou kresbu, ne jen jinou
   barvu: posypka → tečky → šachovnice → spáry → podélné pruhy →
   žilkování. Musí být poznat i na dálku.
0. **Proraž zeď a proběhni střepy.** Musí se ti rozhrnout od nohou a
   vyskočit — a v plném běhu víc než při chůzi.
0. **Rozeběhni se a koukej pod nohy.** Podlaha je z dlaždic a ty se pod
   tebou musí propadat — za tebou zůstává stopa důlků, které se pomalu
   zvedají.
1. **Doběhni ke zdi, na kterou nemáš dost Poweru, a tlač se do ní**
2. Bloky na jejím čele se musí kolem tebe **propadnout** — nejhlouběji
   tam, kde do ní tlačíš, mělčeji do stran
3. Ustup a **koukej se na ten důlek**: musí chvíli zůstat dole a teprve
   pak se pomalu zvednout. Když vystřelí zpátky, je to guma, ne squishy —
   nahlas to.
4. **Seber pickup a počkej u něj.** Musí se vrátit zmáčknutý a pomalu
   se nafouknout, ne vyskočit.

Zóny se mačkají různě: Jelly Flats naplno, Butter Block zhruba z půlky,
Chrome Mile vůbec. Materiál, zvuk i mačkání jdou jedním směrem — od
nejměkčího k nejtvrdšímu.

> V **Settings → Low graphics** se mačkání vypne úplně.

## 4b. Textura tabule

Na čelní straně každé zdi je **mřížka buněk**. Není to obrázek — je to
mřížka prvků, takže se dá rozsvěcet po jedné.

- Zeď se **plní zdola nahoru**, jak sbíráš Power
- Při plném nabití celá mřížka **dýchá**
- V **Settings → Low graphics** mřížka zmizí (je to jediná vrstva se
  stovkami prvků)

Postup je díky tomu vidět na zdi samotné — nemusíš koukat do UI.

## 5. Kolo světa

1. Proraž všech **12 zdí**
2. Toast: `Glass Hall LAP 1 DONE! … walls got tougher`
3. Vrátí tě to na start
4. **První zeď teď stojí 15 Poweru**, ne 8
5. V HUD přibyl řádek `Lap 2 — walls 1.90x tougher`

Když zdi po dojetí zůstanou stejné, kola se nezapisují.

---

## 5b. Hudba

V **Settings** je přepínač **Music**. Do teď nedělal nic, teď zapíná
procedurální podklad — dvě vrstvy, tempo podle světa.

- Zapni a vypni: hudba musí plynule zmizet a vrátit se, ne cvaknout
- **Přepni svět**: tempo se musí změnit
- **Rozjeď combo**: podklad musí zesílit a s pádem řetězu se ztišit
- Při průrazu se ztlumí ambientní dron, ale hudba **nesmí cukat** —
  má vlastní skupinu právě proto

## 5c. Brána do dalšího světa

Za cílem stojí brána se jménem a cenou dalšího světa.

1. Doběhni k ní bez peněz: cena musí být **červená** a nic se nesmí stát.
2. Došetři na ni a vejdi do ní. Svět se koupí a hráče to rovnou přenese.
3. Vrať se a projdi bránou znovu: nápis musí být zelený `ENTER` a projít
   se má bez placení.
4. Za posledním světem žádná brána stát nesmí — není kam.

Kdyby brána nereagovala, hledej dvě věci: chybí jí značka `WorldPortal`
(klient ji nenajde), nebo se posílá špatný tvar — `BuyWorld` chce id,
`EnterWorld` index.

## 5d. Hala kolem dráhy

1. Podívej se ze dráhy do strany: musí být vidět **terasa, vzdálená
   stěna a strop**, ne bezprostřední zeď u ramene.
2. Zkus vyskočit přes zábradlí. **Nesmí to jít** — nad ním je průhledná
   zábrana. Kdyby to šlo, dá se obejít každá zeď a přeskákat celý postup.
3. Na terase stojí obří hračka toho levelu, cukrovinky (hůl, sušenka,
   jahoda, koktejl, kornout) a nad hlavou se vznášejí kry.
4. Nic z toho se nesmí vznášet nad zemí ani prorůstat zábradlím.

## 5e. Dvojnásobek pro celý server

Nad peněženkou se pět minut z každé půlhodiny objeví pruh `×2 COINS`
s odpočtem. Zkontroluj, že po jeho konci zmizí sám a že se během něj
mince opravdu počítají dvojnásobně — nápis, za kterým se nic nemění,
je horší než žádný.

## 5f. Level a hračka jsou jedna věc

Pořadí levelů je zároveň pořadím žebříčku hraček: v levelu, kde stojí
obří máslo, se máslo prodává, a stojí přesně tolik, kolik si tam hráč
může dovolit.

1. Projdi trať a čti **cenovky pod obřími hračkami**. Musí jít nahoru:
   `YOURS FROM THE START` → 2 500 → 30 000 → … → 180 bilionů →
   `BEAT THE LAST WORLD`. Kdyby některá cena skočila dolů, je pořadí
   rozbité.
2. Otevři **Squishies**. U každé hračky je napsané, z kterého levelu je
   (`level 9: Cheese Caves`). Musí to sedět s tím, kolem čeho jsi běžel.
3. Zmáčkni každou hračku, kterou máš: **každá zní jinak**. Máslo se
   odlepí, marshmallow žuchne do ticha, sýr křupne, chrom cvakne.
   Zvuk jde z materiálu levelu, ne z jednoho společného vzorku.
4. Proraž zeď a **kouknij se na obří hračku vedle trati** — musí se
   promáčknout s ní. Marshmallow se propadne skoro celý, chrom se
   skoro nehne.

## 5f2. Vzdálená polovina trati žije taky

Se zapnutým streamingem k hráči doputuje jen okolí. Doběhni proto **až
na konec trati** a zkontroluj, že se i tam:

1. **vznášejí rekvizity** (kry nad hlavou, plovoucí kusy u trati) —
   nesmí stát na místě,
2. **obří hračka se promáčkne**, když prorazíš zeď u ní,
3. **nákupní deska** má na ceduli tvou úroveň a cenu, ne text ze
   serveru,
4. a když si v Settings zapneš **Low graphics** hned u startu, musí
   zůstat zhasnuto i na konci trati — ne se zase rozsvítit, jakmile
   tam doběhneš.

Dřív si klient všechny tři věci sbíral jedním průchodem při stavbě
světa, takže našel jen to, co bylo v tu chvíli načtené — sotva první
třetinu trati.

## 5g. Tabule u startu

1. Vlevo od placu **HOW TO PLAY** se čtyřmi kroky. Musí se dát přečíst
   z místa, kde hráč naběhne, bez chození k ní.
2. Vpravo **DAILY REWARD** se sedmi dny. Sedmý den musí nést jméno
   hračky (`Lucky Star`) — a to samé musí sedět v panelu Daily.
3. Skutečný žebříček stojí opodál. Na novém serveru (nebo ve Studiu bez
   přístupu k API) v něm nesmí být samá pomlčka: první řádek říká
   `BE THE FIRST`, případně `LEADERBOARD OFFLINE`, když se nenačetl.

## 6. Postup a obchod

- **Upgrades**: první úroveň Power stojí **60 mincí**. Po koupi musí
  hodnota `+1` viditelně vyskočit.
- **Speed**: po koupi musí být postava **hned rychlejší**, ne až po respawnu.
- **Kódy**: zadej `LAUNCH` → +5 000 mincí, +50 gemů. Podruhé už nesmí projít.
- **Shop**: nahoře **denní sleva** (jeden boost levněji, `TODAY ONLY`)
  a **směna gemů** — 10 💎 za mince v hodnotě 15 minut tvého příjmu.
- **Truhla zdarma** každých 90 s.
- **Svět 2 (Jelly Cave)** stojí **6 304 097 mincí** — na ten se hraním
  dostaneš za ~12 minut. Na test si dej kód a truhly.

---

## 7. Kosmetika (záložka Style)

- Tři přepínače: **TRAILS / AURAS / SKINS**
- Po **25 průrazech** se odemkne stopa *Spark* → nasadit → musí být
  za postavou vidět
- Zamčené kusy ukazují, **kolik chybí**, ne jen „LOCKED"
- **Skin** změní barvu i materiál postavy
- V **Settings → Low graphics**: stopy a aury zmizí, **skin zůstane**
  (to je záměr — skin nic nestojí)

---

## 8. Rebirth a perky

Rebirth stojí **9 690 000 000 mincí**, takže na normální hraní je to
~1 hodina. Na test si dej hodně kódů, nebo si v `Config.luau` dočasně
sniž `Rebirth.BaseCost`.

Po rebirthu:
- Zpátky ve světě 1, mince a upgrady pryč, **gemy a tituly zůstanou**
- V panelu Rebirth přibyl **1 perk token**
- Dají se koupit jen větve **Muscle Memory** a **Night Shift** —
  zbytek je zamčený a ukazuje, kolik rebirthů potřebuje
- Po koupi perku token zmizí a **nejde utratit podruhé**

---

## 9. Dva hráči najednou

Ve Studiu: **Test → Clients and Servers → 2 players → Start**.

- Vidí se navzájem? Mají nad hlavou titul?
- Vidí jeden druhému **stopu a auru**?
- Rozpadlé kusy zdi **neblokují** druhého hráče (jsou v jiné kolizní skupině)
- Zeď proražená jedním hráčem **nesmí zmizet druhému** — každý má svůj postup
### Vzhled: velké kusy, nopy, poznatelné věci

1. **Nopy všude.** Stěny, podlahové desky a dlaždice mají mít na povrchu
   klasické roblox nopy. Když jsou hladké, přišel o ně `Build.part` —
   je to jediné místo, kde se povrch nastavuje.
2. **Dlaždice jsou velké kusy**, ne mozaika: šest na sedm na úsek, každá
   přes dva kroky, s viditelnou spárou a bokem. Když jsou drobné,
   splynou z výšky očí v jednu plochu.
3. **Obří rekvizity u trati.** V máslovém levelu má vedle trati stát
   šestnáctkrát zvětšené máslo i s papírem a nápisem, v sýrovém sýr
   s dírami. Střídají se strany.
4. **Nákupní desky na trati.** Zelené desky u kraje s cedulí
   `LVL x · 💰 cena`. Stoupni si na ni: kupuje opakovaně, dokud stojíš,
   asi dvakrát za vteřinu. Když na to nemáš, deska zšedne a cena
   zčervená — a nesmí se posílat žádný dotaz na server.
5. Desky se opakují po celé délce, ne jen u startu: v desátém levelu
   se hráč nemá kvůli vylepšení vracet.

### Levely: jedna zeď, jeden svět

1. Proraz první zeď. Za ní musí být **všechno jiné naráz** — podlaha,
   strop, stěny, zvuk kroku i tvar drobností. Když se změní jen barva
   podlahy, nesedí `Zones.at` s tím, co staví `TrackView:buildTiles`.
2. Projdi všech dvanáct. Pořadí: Blob → Marshmallow → Butter → Mochi →
   Jelly → Donut → Peach → Toast → Cheese → Sugar Glass → Chrome → Void.
   Cedule se jménem levelu stojí u každé zdi.
3. Povrch má nést **výzdobu** svého levelu: díry v sýru, posyp na
   koblize, papírový pás na másle, nýty na chromu.
4. **Chodba se prohýbá.** V prvních levelech se pod tebou propadá
   podlaha, panely po stranách i lamely nad hlavou. Na chromu se nesmí
   hnout vůbec nic — `Sag` je tam nula a je to ten rozdíl, kvůli kterému
   je poslední třetina trati cítit jako jiná hra.
5. Za zdí musí být vidět **už další level**, ne ještě ten starý:
   dláždí se tři úseky dopředu a každý si bere vzhled ze svého levelu.

### Squishy v ruce

1. Po startu drž **Pink Blob** v pravé ruce. Musí jet s animací postavy,
   ne plavat vedle ní.
2. Klikni (nebo `E`, nebo ťukni na telefonu). Hračka se má **propadnout
   a pomalu se vrátit** — ne cvaknout zpátky. Tón každého dalšího
   zmáčknutí je vyšší, po vteřině pauzy spadne zase dolů.
3. Power musí naskočit **až podle serveru**. Zkus mačkat co nejrychleji:
   nad pět zmáčknutí za sekundu už se nic nepřidává a je to poznat tím,
   že u hračky přestanou lítat jiskřičky.
4. Panel `5` (SQUISHIES): koupené hračky se dají vzít do ruky a odložit,
   drahé jsou zamčené cenou, poslední dvě mají "REWARD" a koupit nejdou.
5. **Salted Butter**: kvádr musí mít krémový obal a na něm modrý nápis
   `SALTED BUTTER`. Po zmáčknutí se **na chvíli zastaví dole** (lepivost)
   a teprve pak se skoro celou vteřinu vrací.
6. **Cheese Cube**: kostka s pěti dírami. Prst udělá dolík **jen v tom
   rohu, kterého se dotkl** — protilehlá strana se má hnout sotva znatelně.
   Když se srovná celá kostka najednou, rozešel se dosah v `pressToy`
   s velikostí hračky.
7. Vezmi si do ruky tvrdší hračku (Chrome Ball). Musí se mačkat **méně**
   a dávat víc za držení — pokud je to obráceně, rozešly se hodnoty
   v `Live.Squishies` s tím, co dělá `Economy.squeezeValue`.

- **Trade**: pozvi druhého, nabídni hračku, oba potvrďte. Změna nabídky
  musí **zrušit obě potvrzení**.

---

## 10. Ukládání

1. Hraj, něco nakup
2. **Stop**, pak zase **Play**
3. Postup tam musí být

Když ne: buď je vypnuté API Services (žlutý toast), nebo je chyba v
DataService — pošli mi Output.

---

## 10b. Pohyby postavy

Drobnosti, které nejsou vidět v kódu, ale jsou cítit:

- **Zatoč za běhu** — postava se musí položit do zatáčky jako motorkář,
  ne měnit směr, jako by stála na kolejích
- **Zpomal** — kroky a rozmach paží musí zpomalit **s tebou**, ne běžet
  dál na místě
- **Skoč a dopadni** — u nohou musí odletět prach a zůstat ležet, ne
  táhnout se za tebou

## 11. Mobil

Ve Studiu: **Test → Device → iPhone / tablet**.

- Levá mřížka ikon se složí do **jednoho sloupce**
- Nic nesmí přetékat mimo obrazovku ani se překrývat
- Karta comba vpravo nesmí zakrývat promo nabídky

---

## Co mi poslat, když něco nesedí

1. **Celý text červené chyby z Output** (i s cestou k souboru a číslem řádku)
2. Co jsi dělal těsně předtím
3. Screenshot, když jde o vzhled

Chyba typu `attempt to index nil` nebo `Remotes.Neco` je pro mě opravitelná
během chvilky, když mám ten řádek. Bez něj hádám.

# Assety — kde brát zvuky, textury a obrázky

Power Smash je záměrně postavený tak, že **nepotřebuje jediný nahraný
asset**. Všechno, co hraje a co je vidět, je buď spočítané kódem, nebo
zabalené v každém Roblox klientu. Díky tomu se dá hra otevřít ve Studiu
a hned ji spustit — bez čekání, bez cizích práv a bez rozbitých ID.

Tenhle soubor je návod, **jak si to vylepšit vlastními assety**, až
budeš chtít. Nic z toho není povinné.

---

## 1. Proč tu nejsou cizí `rbxassetid://`

Roblox má u nahraného zvuku systém soukromí: **nahraný asset je nejdřív
soukromý a použít ho může jen ten, kdo ho nahrál**, dokud práva výslovně
nedá dál konkrétnímu člověku nebo konkrétní hře.

Prakticky to znamená: ID opsané z YouTube videa nebo z nějakého seznamu
"top 100 Roblox sound IDs" **ti ve hře hrát nebude**. Ne proto, že by to
bylo špatně napsané — prostě k němu nemáš práva. A protože se to nijak
neohlásí, vypadá to jako chyba v kódu.

Proto celá hra stojí na `rbxasset://` (viz níž) a vlastní ID se dávají
jen do jednoho místa, kde je jasné, co se stane, když nesedí.

---

## 2. Co je v klientu zadarmo (`rbxasset://`)

`rbxasset://` nejsou nahrané assety, ale soubory, které Roblox posílá
s každým klientem. Jsou vždycky dostupné, nikomu nepatří a nepotřebují
žádná práva.

**Zvuky** — používá je `src/shared/Assets.luau`:

```
rbxasset://sounds/action_footsteps_plastic.mp3
rbxasset://sounds/action_jump_land.mp3
rbxasset://sounds/action_jump.mp3
rbxasset://sounds/action_get_up.mp3
rbxasset://sounds/action_falling.mp3
rbxasset://sounds/action_swim.mp3
rbxasset://sounds/impact_water.mp3
```

Je jich málo, ale to nevadí: ASMR nedělá jeden dokonalý sample, ale
**vrstvení**. Jeden krok přehraný třikrát v různých výškách a s posunem
o pár setin sekundy zní jako praskající sklo; ten samý krok hluboko
a pomalu zní jako dopad čokolády. Recepty v `Assets.Smash` z toho
skládají zvuk každého světa.

**Obrázky částic** — `Assets.Particles`:

```
rbxasset://textures/particles/sparkles_main.dds
rbxasset://textures/particles/smoke_main.dds
rbxasset://textures/particles/fire_main.dds
```

Do teď neměl žádný emitter nastavenou `Texture`, takže úplně všechno —
střepy ze zdi, prach pod nohama, stopy za postavou i konfety z milníku —
používalo tu samou výchozí jiskřičku. Deset různých efektů, které
vypadají stejně, splyne v jeden.

> **Když se cesta nenajde**, částice se nevykreslí vůbec — efekt zmizí,
> hra nespadne. Kdyby ti po updatu klienta zmizel prach u nohou nebo
> rozlet ze zdi, nastav v `Assets.Particles` tu položku na `""` a vrátí
> se výchozí jiskřička.

---

## 3. Kde brát vlastní zvuky zadarmo

**Creator Store přímo ve Studiu.** Roblox v něm má přes sto tisíc
profesionálně nahraných zvuků a hudby, které jsou zdarma a smí se
použít v jakékoliv hře.

Postup:

1. Ve Studiu **View → Toolbox**
2. Nahoře přepni záložku na **Creator Store**
3. V rozbalovacím seznamu vyber **Audio**
4. Vyhledej (třeba `squish`, `pop`, `glass break`, `whoosh`)
5. Na výsledku **pravé tlačítko → Copy Asset ID**

Získané ID vlož do `Assets.Override` v `src/shared/Assets.luau`:

```lua
Assets.Override = {
    Smash_Glass = "rbxassetid://1234567890",
    Pickup = "rbxassetid://9876543210",
}
```

Recept se pak nahradí tvým zvukem a **všechno ostatní zůstane**. Nic
dalšího se přepisovat nemusí.

Klíče, které dávají smysl přepsat:

| Klíč | Kdy zní |
|---|---|
| `Smash_<IdSvěta>` | průraz zdi v tom světě (`Smash_Glass`, `Smash_Jelly`, …) |
| `Pickup` | sebrání `+1` |
| `Squeeze_<Materiál>` | zmáčknutí hračky podle materiálu |
| `Purchase` | nákup |
| `Ready` | vstup do světa |
| `Lucky` | šťastná zeď |

---

## 4. Vlastní nahrávky

Když si chceš nahrát vlastní ASMR:

- soubor musí být **do 20 MB a do 7 minut**, vzorkovací frekvence
  **nejvýš 48 kHz**
- **ID Verified** účet uploadne **2 000** zvuků za 30 dní, neověřený
  **100**
- nahraný zvuk je nejdřív soukromý — v Creator Dashboardu mu musíš dát
  **práva pro tuhle hru**, jinak se v ní nepřehraje

Pak už jen ID do `Assets.Override`, stejně jako výš.

---

## 5. Textury

Jediné místo, kde hra počítá s nahranou texturou, je

```lua
Assets.Textures = {
    Barrier = "",   -- posouvá se po zdi nahoru jako energetické pole
}
```

Prázdná hodnota znamená "nedělej nic" — zeď pak vypadá dobře i bez ní,
protože pruhy na ní kreslí `Textures.energyField` Beamy, které žádný
obrázek nepotřebují.

Když tam něco dáš, ber **bezešvou (tileable)** texturu, jinak bude na
zdi vidět mřížka spojů. V Toolboxu je to **Creator Store → Images**,
zase přes **Copy Asset ID**.

---

## 6. Modely a packy

Hra si **staví celý svět kódem** (`WorldService`, `Toy`, `Props`), takže
žádný model z Toolboxu nepotřebuje. Je to schválně: model z Toolboxu
s sebou umí přinést i skript, který tam nemá co dělat, a stavěný svět
se dá měnit číslem v `Config`, ne přesouváním dílů myší.

Když přesto budeš chtít použít hotový model:

1. ber ho jen z **Creator Store**, ne z výsledků "Marketplace" od
   neznámých účtů
2. po vložení otevři **Explorer** a projdi, jestli v něm nejsou
   `Script` ani `LocalScript`, které tam nepatří
3. rekvizity patří do `src/shared/Props.luau`, aby je stavěl svět, ne
   ruka

---

## 7. Co ověřit po každé výměně

1. **Zvuk**: dej Play a projdi zeď. Když je ticho, ID nesedí nebo k němu
   nemáš práva — v Output je varování o zvuku, ne o skriptu.
2. **Částice**: skoč a dopadni. Prach musí být obláček. Když nic
   nevidíš, nesedí cesta v `Assets.Particles`.
3. **Textura zdi**: musí navazovat. Vidíš-li čtvercovou mřížku, není
   bezešvá.

Zbytek postupu, co proklikat, je v `docs/TESTOVANI.md`.

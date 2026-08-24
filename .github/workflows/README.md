# CI

`check.yml` běží na každý push a pull request. Dělá čtyři věci:

1. **Zkompiluje všechny `.luau` moduly.** Chytí překlepy a syntaktické
   chyby dřív, než se objeví ve Studiu jako chyba za běhu u jednoho hráče.
2. **Statická kontrola** (`tools/lint.py`) — hlavně že každý použitý
   remote existuje v definicích. Luau je dynamický, takže
   `Remotes.Neexistuje` se v pohodě zkompiluje a spadne až za běhu.
   Přesně tohle se v projektu jednou stalo: osm remotů se používalo,
   ale nebylo definováno, a hra by vůbec nenaběhla.
3. **Pustí testy** z `tests/*.spec.luau`. Kromě čisté logiky (zámek
   profilu, obchod, omezovač volání) mezi ně patří `Boot.spec.luau`,
   který **skutečně nastartuje server** proti náhradě Roblox prostředí.
   Tenhle test vznikl poté, co v projektu několik kol seděla chyba,
   kvůli které hra nemohla naběhnout, a build byl celou dobu zelený.
4. **Pustí simulaci ekonomiky** na skutečných modulech hry a selže, pokud
   se nějaký svět stane nedosažitelným.
5. **Ověří smyčku rebirthů** — že je první rebirth dosažitelný do 24 hodin.

Poslední dva kroky jsou důležitější, než vypadají: změna čísel v `Config`
nebo `Live` se vždycky zkompiluje, ale klidně může rozbít tempo hry tak,
že se to pozná až po vydání.

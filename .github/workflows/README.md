# CI

`check.yml` běží na každý push a pull request. Dělá čtyři věci:

1. **Zkompiluje všechny `.luau` moduly.** Chytí překlepy a syntaktické
   chyby dřív, než se objeví ve Studiu jako chyba za běhu u jednoho hráče.
2. **Statická kontrola** (`tools/lint.py`) — hlavně že každý použitý
   remote existuje v definicích. Luau je dynamický, takže
   `Remotes.Neexistuje` se v pohodě zkompiluje a spadne až za běhu.
   Přesně tohle se v projektu jednou stalo: osm remotů se používalo,
   ale nebylo definováno, a hra by vůbec nenaběhla.
3. **Pustí testy** z `tests/*.spec.luau` — čistá logika bez Roblox API,
   hlavně zámek profilu.
4. **Pustí simulaci ekonomiky** na skutečných modulech hry a selže, pokud
   se nějaký svět stane nedosažitelným.
5. **Ověří smyčku rebirthů** — že je první rebirth dosažitelný do 24 hodin.

Poslední dva kroky jsou důležitější, než vypadají: změna čísel v `Config`
nebo `Live` se vždycky zkompiluje, ale klidně může rozbít tempo hry tak,
že se to pozná až po vydání.

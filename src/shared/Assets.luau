--!strict
--[[
	Assets — jediné místo, kde se řeší, jaký zvuk a jaká textura se použije.

	══ Proč `rbxasset://` a ne `rbxassetid://` ══

	Roblox od audio updatu nedovolí použít cizí NAHRANÉ audio: `rbxassetid://`
	od jiného tvůrce je soukromé a v cizí hře se nepřehraje. Proto celá hra
	stojí na `rbxasset://` — to nejsou nahrané assety, ale soubory, které
	Roblox posílá v každém klientu. Jsou vždycky dostupné, nikomu nepatří
	a nepotřebují žádná práva.

	Zvuků je jich jen pár, ale to nevadí: ASMR nedělá jeden dokonalý sample,
	ale VRSTVENÍ. Jeden krok přehraný třikrát v různých výškách a s posunem
	o pár setin sekundy zní jako praskající sklo. Ten samý krok hluboko
	a pomalu zní jako dopad čokolády. Recepty níž z toho skládají zvuk
	každého světa.

	══ Vlastní zvuky ══

	Až si nahraješ vlastní ASMR nahrávky přes Creator Dashboard, dej jejich
	ID do `Assets.Override`. Recept se pak nahradí tvým zvukem a všechno
	ostatní zůstane. Nic dalšího se přepisovat nemusí.
]]

local Assets = {}

-- Zvuky zabalené v každém Roblox klientu (viz RbxCharacterSounds).
-- Tyhle cesty jsou stabilní a fungují offline i v neposlouchaném zážitku.
local STEP = "rbxasset://sounds/action_footsteps_plastic.mp3"
local LAND = "rbxasset://sounds/action_jump_land.mp3"
local JUMP = "rbxasset://sounds/action_jump.mp3"
local RUSTLE = "rbxasset://sounds/action_get_up.mp3"
local WHOOSH = "rbxasset://sounds/action_falling.mp3"
local SWIM = "rbxasset://sounds/action_swim.mp3"
local SPLASH = "rbxasset://sounds/impact_water.mp3"

export type Layer = {
	Id: string,
	Pitch: number,
	Volume: number,
	Delay: number?,
	--[[
		Ohyb výšky: kam se má tón během přehrávání sklouznout a jak dlouho
		to má trvat.

		Tohle je ta jediná věc, která dělá "squishy". Krátký vzorek
		s pevnou výškou zní jako ťuknutí, ať ho ohneš ekvalizérem jakkoliv.
		Ten samý vzorek, který během desetiny sekundy sjede o oktávu dolů,
		zní jako mokré stlačení — protože přesně to dělá měkký materiál
		fyzicky: jak se hmota stlačuje, klesá její rezonanční frekvence.

		Nahoru to funguje stejně: sklouznutí vzhůru zní jako odskok.
	]]
	Bend: number?,
	BendTime: number?,
}

export type Recipe = { Layer }

--[[
	Vlastní ID. Klíč = jméno receptu ("Smash_Glass", "Pickup", …).
	Hodnota = `rbxassetid://…` tvého nahraného zvuku.

	Příklad:
		Assets.Override = {
			Smash_Glass = "rbxassetid://1234567890",
			Pickup = "rbxassetid://9876543210",
		}
]]
Assets.Override = {} :: { [string]: string }

-- Rozpad bariéry: každý svět má vlastní charakter ------------------------------

Assets.Smash = {
	-- Sklo: ostré, vysoké, rozsypané do několika úderů
	Glass = {
		{ Id = STEP, Pitch = 2.6, Volume = 0.55 },
		{ Id = LAND, Pitch = 1.9, Volume = 0.45 },
		{ Id = STEP, Pitch = 3.1, Volume = 0.35, Delay = 0.045 },
		{ Id = STEP, Pitch = 2.85, Volume = 0.28, Delay = 0.095 },
		{ Id = STEP, Pitch = 3.4, Volume = 0.2, Delay = 0.16 },
	},
	-- Želé: mokré, měkké, bez ostrých hran
	Jelly = {
		{ Id = SPLASH, Pitch = 1.35, Volume = 0.7 },
		{ Id = SWIM, Pitch = 1.5, Volume = 0.4, Delay = 0.03 },
		{ Id = SPLASH, Pitch = 0.9, Volume = 0.35, Delay = 0.11 },
	},
	-- Led: křupavé praskání, hodně krátkých úderů rychle za sebou
	Ice = {
		{ Id = STEP, Pitch = 3.2, Volume = 0.5 },
		{ Id = STEP, Pitch = 2.9, Volume = 0.4, Delay = 0.03 },
		{ Id = STEP, Pitch = 3.6, Volume = 0.35, Delay = 0.06 },
		{ Id = STEP, Pitch = 3.3, Volume = 0.3, Delay = 0.09 },
		{ Id = LAND, Pitch = 2.2, Volume = 0.35, Delay = 0.02 },
	},
	-- Čokoláda: hluboké, tupé prasknutí
	Chocolate = {
		{ Id = LAND, Pitch = 0.55, Volume = 0.8 },
		{ Id = STEP, Pitch = 0.7, Volume = 0.45, Delay = 0.05 },
		{ Id = LAND, Pitch = 0.75, Volume = 0.35, Delay = 0.13 },
	},
	-- Neon: elektrické, syčivé
	Neon = {
		{ Id = SWIM, Pitch = 2.4, Volume = 0.55 },
		{ Id = WHOOSH, Pitch = 2.0, Volume = 0.4 },
		{ Id = STEP, Pitch = 3.5, Volume = 0.3, Delay = 0.05 },
		{ Id = SWIM, Pitch = 1.8, Volume = 0.3, Delay = 0.12 },
	},
	-- Void: dunivé, s dlouhým ocasem
	Void = {
		{ Id = LAND, Pitch = 0.4, Volume = 0.9 },
		{ Id = WHOOSH, Pitch = 0.5, Volume = 0.55, Delay = 0.02 },
		{ Id = SWIM, Pitch = 0.6, Volume = 0.4, Delay = 0.15 },
		{ Id = LAND, Pitch = 0.5, Volume = 0.3, Delay = 0.3 },
	},
	--[[
		Mlhovina: vzduch bez ozvěny. Průraz se rozfoukne do stran místo
		aby prasknul — je to jediný svět, ve kterém se nic netříští.
	]]
	Nebula = {
		{ Id = WHOOSH, Pitch = 0.7, Volume = 0.7 },
		{ Id = SWIM, Pitch = 1.1, Volume = 0.45, Delay = 0.04 },
		{ Id = WHOOSH, Pitch = 1.5, Volume = 0.35, Delay = 0.14 },
		{ Id = SWIM, Pitch = 0.8, Volume = 0.25, Delay = 0.28 },
	},
	-- Výheň: tupý úder a po něm praskání, jak zeď dohořívá
	Solar = {
		{ Id = LAND, Pitch = 0.5, Volume = 0.95 },
		{ Id = STEP, Pitch = 0.9, Volume = 0.5, Delay = 0.04 },
		{ Id = STEP, Pitch = 1.2, Volume = 0.35, Delay = 0.12 },
		{ Id = STEP, Pitch = 1.05, Volume = 0.25, Delay = 0.21 },
		{ Id = LAND, Pitch = 0.65, Volume = 0.3, Delay = 0.32 },
	},
	-- Kvantum: čistý zvon, žádné harašení. Zeď se nerozbije, zazvoní.
	Quantum = {
		{ Id = STEP, Pitch = 3.9, Volume = 0.5 },
		{ Id = SWIM, Pitch = 2.6, Volume = 0.4, Delay = 0.02 },
		{ Id = STEP, Pitch = 2.6, Volume = 0.3, Delay = 0.18 },
	},
	--[[
		Zahrada: všechno naráz a hodně nízko. Je to poslední svět
		a průraz v něm musí znít jako událost, ne jako další zeď.
	]]
	Infinity = {
		{ Id = LAND, Pitch = 0.45, Volume = 1 },
		{ Id = STEP, Pitch = 2.2, Volume = 0.5, Delay = 0.02 },
		{ Id = WHOOSH, Pitch = 0.8, Volume = 0.55, Delay = 0.06 },
		{ Id = SWIM, Pitch = 1.4, Volume = 0.4, Delay = 0.16 },
		{ Id = LAND, Pitch = 0.6, Volume = 0.35, Delay = 0.34 },
	},
	--[[
		Útes: sklo pod vodou. Vysoký cinkot s doběhem dolů — jako když
		praskne led na hladině a zvuk se v ní hned utopí.
	]]
	Prism = {
		{ Id = STEP, Pitch = 3.4, Volume = 0.7, Bend = 0.5, BendTime = 0.3 },
		{ Id = SPLASH, Pitch = 1.6, Volume = 0.45, Delay = 0.04 },
		{ Id = STEP, Pitch = 2.8, Volume = 0.3, Delay = 0.14 },
		{ Id = SWIM, Pitch = 1.1, Volume = 0.3, Delay = 0.22 },
	},
	--[[
		Bouře z vaty: skoro žádný náraz, samý šum. Měkký svět musí znít
		tlumeně, jinak je z vaty beton.
	]]
	Cotton = {
		{ Id = RUSTLE, Pitch = 0.9, Volume = 0.8 },
		{ Id = WHOOSH, Pitch = 1.2, Volume = 0.5, Delay = 0.05 },
		{ Id = RUSTLE, Pitch = 1.3, Volume = 0.35, Delay = 0.16 },
	},
	--[[
		Kovárna: jedna těžká rána a kovový dozvuk. Nic měkkého.
	]]
	Obsidian = {
		{ Id = LAND, Pitch = 0.4, Volume = 1 },
		{ Id = LAND, Pitch = 0.55, Volume = 0.5, Delay = 0.07 },
		{ Id = STEP, Pitch = 1.4, Volume = 0.4, Delay = 0.13, Bend = 0.7, BendTime = 0.4 },
	},
	--[[
		Vrchol: vysoký, čistý a dlouhý. Poslední svět v řadě — průraz
		v něm má znít jako zvon, ne jako rána.
	]]
	Aurora = {
		{ Id = SWIM, Pitch = 1.8, Volume = 0.8, Bend = 2.6, BendTime = 0.5 },
		{ Id = STEP, Pitch = 3.2, Volume = 0.45, Delay = 0.03 },
		{ Id = LAND, Pitch = 0.9, Volume = 0.5, Delay = 0.1 },
		{ Id = SWIM, Pitch = 2.4, Volume = 0.35, Delay = 0.28 },
	},
}

-- Ostatní události ---------------------------------------------------------------

Assets.Recipes = {
	-- Sebrání "+1". Výška se dopočítává za běhu (stoupá při rychlém sbírání),
	-- tady je jen základní barva zvuku.
	Pickup = {
		{ Id = STEP, Pitch = 2.2, Volume = 0.22 },
	},
	-- Kritický pickup (Luck)
	Lucky = {
		{ Id = STEP, Pitch = 2.6, Volume = 0.3 },
		{ Id = SWIM, Pitch = 2.2, Volume = 0.25, Delay = 0.04 },
		{ Id = STEP, Pitch = 3.4, Volume = 0.25, Delay = 0.08 },
	},
	--[[
		Odrazový můstek. Ohyb nahoru je celý ten zvuk: pružina, která
		hráče vystřelí, musí znít jako něco, co se napíná a povolí, ne
		jako ťuknutí — proto vzorek během desetiny sekundy vyjede
		o oktávu výš.
	]]
	Bounce = {
		{ Id = LAND, Pitch = 1.1, Volume = 0.45, Bend = 2.3, BendTime = 0.12 },
		{ Id = SWIM, Pitch = 1.6, Volume = 0.3, Delay = 0.03 },
		{ Id = WHOOSH, Pitch = 1.4, Volume = 0.22, Delay = 0.06 },
	},
	-- Náraz do bariéry, na kterou hráč nemá
	Blocked = {
		{ Id = LAND, Pitch = 0.65, Volume = 0.4 },
		{ Id = RUSTLE, Pitch = 0.8, Volume = 0.25, Delay = 0.05 },
	},
	-- Bariéra je nabitá a čeká na proražení
	Ready = {
		{ Id = SWIM, Pitch = 2.0, Volume = 0.3 },
		{ Id = STEP, Pitch = 3.0, Volume = 0.2, Delay = 0.07 },
	},
	-- Dokončené kolo
	WorldClear = {
		{ Id = SWIM, Pitch = 1.4, Volume = 0.5 },
		{ Id = LAND, Pitch = 1.6, Volume = 0.45, Delay = 0.09 },
		{ Id = SWIM, Pitch = 1.9, Volume = 0.4, Delay = 0.2 },
		{ Id = LAND, Pitch = 2.1, Volume = 0.35, Delay = 0.32 },
	},
	-- Nákup a rebirth
	Purchase = {
		{ Id = STEP, Pitch = 2.4, Volume = 0.3 },
		{ Id = SWIM, Pitch = 1.9, Volume = 0.25, Delay = 0.05 },
	},
	Rebirth = {
		{ Id = WHOOSH, Pitch = 0.7, Volume = 0.6 },
		{ Id = SWIM, Pitch = 1.2, Volume = 0.5, Delay = 0.25 },
		{ Id = LAND, Pitch = 1.8, Volume = 0.5, Delay = 0.55 },
	},
	-- Odemčená stopa nebo aura: krátké zvednutí, ne fanfára —
	-- odemyká se za běhu a nesmí přebít zvuk průrazu.
	Unlock = {
		{ Id = SWIM, Pitch = 1.7, Volume = 0.32 },
		{ Id = STEP, Pitch = 2.6, Volume = 0.22, Delay = 0.06 },
		{ Id = STEP, Pitch = 3.2, Volume = 0.18, Delay = 0.12 },
	},
	-- Klik v menu
	Click = {
		{ Id = STEP, Pitch = 2.8, Volume = 0.18 },
	},
}

-- Zvuk terénu -------------------------------------------------------------------
--[[
	Krok a průraz podle toho, na čem hráč zrovna stojí.

	Nestačí měnit výšku jednoho vzorku — tak vznikne "stejný zvuk, jen
	vyšší", ne jiný materiál. Rozdíl dělá kombinace tří věcí:

	  1. **z čeho** — mokrý vzorek (SPLASH, SWIM) proti suchému (STEP, LAND)
	  2. **kolik vrstev a jak posunutých** — jedna vrstva je ťuknutí,
	     tři těsně za sebou jsou křupnutí
	  3. **ohyb výšky** — sjezd dolů = stlačení měkké hmoty, výjezd
	     nahoru = odskok

	Právě třetí bod je to, co dělá "squishy", a do teď v projektu nebyl.

	Zóny jdou od nejměkčí k nejtvrdší, takže se dá poslouchat, jak daleko
	hráč je, i se zavřenýma očima.
]]
Assets.Terrain = {
	--[[
		Karamel: táhlé mlasknutí. Nejlepivější povrch na trati — krok
		se z něj odlepuje, místo aby se odrazil.
	]]
	Taffy = {
		Step = {
			{ Id = STEP, Pitch = 3.1, Volume = 0.2 },
			{ Id = SPLASH, Pitch = 1.7, Volume = 0.1, Delay = 0.02 },
		},
		Smash = {
			{ Id = STEP, Pitch = 3.4, Volume = 0.7, Bend = 0.5, BendTime = 0.3 },
			{ Id = SPLASH, Pitch = 1.5, Volume = 0.4, Delay = 0.05 },
		},
		Squeeze = {
			{ Id = STEP, Pitch = 2.9, Volume = 0.3, Bend = 1.6, BendTime = 0.14 },
		},
	},
	--[[
		Vafle: suché křupnutí. Krok po ní zní jako když praskne kůrka.
	]]
	Waffle = {
		Step = {
			{ Id = RUSTLE, Pitch = 1.1, Volume = 0.16 },
		},
		Smash = {
			{ Id = RUSTLE, Pitch = 0.9, Volume = 0.7 },
			{ Id = WHOOSH, Pitch = 1.3, Volume = 0.35, Delay = 0.05 },
		},
		Squeeze = {
			{ Id = RUSTLE, Pitch = 1.4, Volume = 0.32, Bend = 0.6, BendTime = 0.2 },
		},
	},
	--[[
		Želé: pružné plesknutí s doběhem nahoru — povrch, který se pod
		nohou prohne a zase vrátí.
	]]
	Gummy = {
		Step = {
			{ Id = LAND, Pitch = 0.6, Volume = 0.24 },
			{ Id = STEP, Pitch = 1.2, Volume = 0.12, Delay = 0.03 },
		},
		Smash = {
			{ Id = LAND, Pitch = 0.42, Volume = 0.9 },
			{ Id = STEP, Pitch = 1.3, Volume = 0.4, Delay = 0.08, Bend = 0.6, BendTime = 0.36 },
		},
		Squeeze = {
			{ Id = LAND, Pitch = 0.9, Volume = 0.3, Bend = 0.5, BendTime = 0.22 },
		},
	},

	-- Blob: mokré plesknutí a hluboký sjezd; nejměkčí věc na trati
	Blob = {
		Step = {
			{ Id = SPLASH, Pitch = 0.68, Volume = 0.28, Bend = 0.4, BendTime = 0.18 },
			{ Id = SWIM, Pitch = 0.8, Volume = 0.16, Delay = 0.03, Bend = 0.5, BendTime = 0.22 },
		},
		Smash = {
			{ Id = SPLASH, Pitch = 0.72, Volume = 0.75, Bend = 0.32, BendTime = 0.34 },
			{ Id = SWIM, Pitch = 0.95, Volume = 0.45, Delay = 0.05, Bend = 0.45, BendTime = 0.4 },
			{ Id = SPLASH, Pitch = 0.5, Volume = 0.4, Delay = 0.18, Bend = 0.28, BendTime = 0.45 },
		},
	},
	-- Marshmallow: tlumené žuchnutí, které se propadne do ticha
	Foam = {
		Step = {
			{ Id = LAND, Pitch = 0.62, Volume = 0.22, Bend = 0.46, BendTime = 0.14 },
			{ Id = RUSTLE, Pitch = 0.8, Volume = 0.12, Delay = 0.03 },
		},
		Smash = {
			{ Id = LAND, Pitch = 0.5, Volume = 0.7, Bend = 0.32, BendTime = 0.34 },
			{ Id = RUSTLE, Pitch = 0.7, Volume = 0.4, Delay = 0.05, Bend = 0.45, BendTime = 0.3 },
			{ Id = WHOOSH, Pitch = 0.45, Volume = 0.3, Delay = 0.14 },
		},
	},
	--[[
		Máslo: lepkavé odtržení. Sjezd dolů a hned zpátky nahoru — přesně
		to, co je slyšet, když se prst odlepí od hračky z referencí.
	]]
	Butter = {
		Step = {
			{ Id = RUSTLE, Pitch = 1.05, Volume = 0.22, Bend = 0.85, BendTime = 0.12 },
			{ Id = SPLASH, Pitch = 0.85, Volume = 0.14, Delay = 0.04, Bend = 1.3, BendTime = 0.14 },
		},
		Smash = {
			{ Id = RUSTLE, Pitch = 0.85, Volume = 0.62, Bend = 1.5, BendTime = 0.24 },
			{ Id = SPLASH, Pitch = 1.1, Volume = 0.5, Delay = 0.06, Bend = 0.7, BendTime = 0.3 },
			{ Id = LAND, Pitch = 1, Volume = 0.35, Delay = 0.18 },
		},
	},
	-- Mochi: měkké plesknutí bez ocasu, jako když se těsto slehne
	Mochi = {
		Step = {
			{ Id = LAND, Pitch = 0.9, Volume = 0.2, Bend = 0.55, BendTime = 0.12 },
			{ Id = SPLASH, Pitch = 1.3, Volume = 0.08, Delay = 0.02, Bend = 0.6, BendTime = 0.14 },
		},
		Smash = {
			{ Id = LAND, Pitch = 0.78, Volume = 0.7, Bend = 0.42, BendTime = 0.3 },
			{ Id = SPLASH, Pitch = 1.15, Volume = 0.4, Delay = 0.05, Bend = 0.55, BendTime = 0.32 },
			{ Id = RUSTLE, Pitch = 0.95, Volume = 0.22, Delay = 0.14 },
		},
	},
	-- Želé: mokré stlačení, hluboký sjezd, žádná ostrá hrana
	Jelly = {
		Step = {
			{ Id = SPLASH, Pitch = 0.75, Volume = 0.3, Bend = 0.42, BendTime = 0.16 },
			{ Id = SWIM, Pitch = 0.9, Volume = 0.18, Delay = 0.02, Bend = 0.55, BendTime = 0.2 },
		},
		Smash = {
			{ Id = SPLASH, Pitch = 0.85, Volume = 0.75, Bend = 0.35, BendTime = 0.3 },
			{ Id = SWIM, Pitch = 1.1, Volume = 0.45, Delay = 0.04, Bend = 0.5, BendTime = 0.35 },
			{ Id = SPLASH, Pitch = 0.55, Volume = 0.4, Delay = 0.16, Bend = 0.3, BendTime = 0.4 },
		},
	},
	-- Kobliha: cukrové zakřupnutí navrchu a měkký spodek pod ním
	Donut = {
		Step = {
			{ Id = STEP, Pitch = 1.6, Volume = 0.16 },
			{ Id = LAND, Pitch = 0.95, Volume = 0.16, Delay = 0.02, Bend = 0.6, BendTime = 0.12 },
		},
		Smash = {
			{ Id = STEP, Pitch = 1.8, Volume = 0.5 },
			{ Id = LAND, Pitch = 0.88, Volume = 0.6, Delay = 0.04, Bend = 0.5, BendTime = 0.3 },
			{ Id = RUSTLE, Pitch = 1.4, Volume = 0.3, Delay = 0.12 },
		},
	},
	-- Broskev: šťavnaté prasknutí slupky, pod ním dužina
	Peach = {
		Step = {
			{ Id = SPLASH, Pitch = 1.15, Volume = 0.2, Bend = 0.7, BendTime = 0.12 },
			{ Id = RUSTLE, Pitch = 1.25, Volume = 0.1, Delay = 0.03 },
		},
		Smash = {
			{ Id = SPLASH, Pitch = 1.05, Volume = 0.7, Bend = 0.6, BendTime = 0.28 },
			{ Id = SWIM, Pitch = 1.3, Volume = 0.35, Delay = 0.05, Bend = 0.8, BendTime = 0.34 },
			{ Id = LAND, Pitch = 0.85, Volume = 0.3, Delay = 0.16 },
		},
	},
	-- Chleba: suché křupnutí kůrky a dutý spodek
	Bread = {
		Step = {
			{ Id = RUSTLE, Pitch = 0.95, Volume = 0.22 },
			--[[
				Ohyb i tady, i když chleba zní suše. Kůrka nahoře křupne,
				ale střídka pod ní se stlačí — a hráč to musí slyšet,
				jinak z měkkého levelu bude jen jinak barevná podlaha.
			]]
			{ Id = LAND, Pitch = 1.1, Volume = 0.14, Delay = 0.03, Bend = 0.72, BendTime = 0.14 },
		},
		Smash = {
			{ Id = RUSTLE, Pitch = 0.8, Volume = 0.65 },
			{ Id = LAND, Pitch = 0.95, Volume = 0.5, Delay = 0.04 },
			{ Id = RUSTLE, Pitch = 1.35, Volume = 0.3, Delay = 0.12 },
			{ Id = WHOOSH, Pitch = 0.7, Volume = 0.2, Delay = 0.2 },
		},
	},
	-- Sýr: tupé plesknutí s krátkým odtržením, hutnější než máslo
	Cheese = {
		Step = {
			{ Id = LAND, Pitch = 1.25, Volume = 0.2, Bend = 0.8, BendTime = 0.1 },
			{ Id = RUSTLE, Pitch = 1.4, Volume = 0.08, Delay = 0.02 },
		},
		Smash = {
			{ Id = LAND, Pitch = 1.1, Volume = 0.7, Bend = 0.72, BendTime = 0.24 },
			{ Id = RUSTLE, Pitch = 1.2, Volume = 0.4, Delay = 0.05, Bend = 1.2, BendTime = 0.26 },
			{ Id = SPLASH, Pitch = 0.9, Volume = 0.28, Delay = 0.15 },
		},
	},
	-- Sklo: ostré, vysoké, rozsypané do několika úderů rychle za sebou
	Glass = {
		Step = {
			{ Id = STEP, Pitch = 2.4, Volume = 0.2 },
			{ Id = STEP, Pitch = 3.1, Volume = 0.1, Delay = 0.025 },
		},
		Smash = {
			{ Id = STEP, Pitch = 2.7, Volume = 0.6 },
			{ Id = STEP, Pitch = 3.3, Volume = 0.45, Delay = 0.035 },
			{ Id = STEP, Pitch = 3.9, Volume = 0.3, Delay = 0.07 },
			{ Id = STEP, Pitch = 3.5, Volume = 0.22, Delay = 0.12 },
			{ Id = SWIM, Pitch = 2.6, Volume = 0.18, Delay = 0.05, Bend = 3.4, BendTime = 0.5 },
		},
	},
	-- Kov: úder s dlouhým kovovým doznívkem, který ještě stoupne
	Chrome = {
		Step = {
			{ Id = LAND, Pitch = 1.9, Volume = 0.22 },
			{ Id = STEP, Pitch = 2.6, Volume = 0.1, Delay = 0.02 },
		},
		Smash = {
			{ Id = LAND, Pitch = 1.7, Volume = 0.75 },
			{ Id = SWIM, Pitch = 1.9, Volume = 0.4, Delay = 0.03, Bend = 2.6, BendTime = 0.7 },
			{ Id = LAND, Pitch = 2.4, Volume = 0.3, Delay = 0.1 },
			{ Id = STEP, Pitch = 3.2, Volume = 0.2, Delay = 0.2 },
		},
	},
	-- Void: nasáté ticho — všechno sjíždí dolů a mizí
	Void = {
		Step = {
			{ Id = WHOOSH, Pitch = 0.5, Volume = 0.18, Bend = 0.3, BendTime = 0.25 },
		},
		Smash = {
			{ Id = WHOOSH, Pitch = 0.55, Volume = 0.7, Bend = 0.28, BendTime = 0.55 },
			{ Id = SWIM, Pitch = 0.7, Volume = 0.45, Delay = 0.08, Bend = 0.35, BendTime = 0.6 },
			{ Id = LAND, Pitch = 0.42, Volume = 0.4, Delay = 0.24, Bend = 0.25, BendTime = 0.5 },
		},
	},
}

-- Recept terénu; neznámé id spadne na sklo, aby nikdy nevznikl němý krok.
function Assets.terrain(zoneId: string, kind: string): Recipe
	local set = Assets.Terrain[zoneId] or Assets.Terrain.Glass
	return (if kind == "Smash" then set.Smash else set.Step) :: Recipe
end

-- Hudba ------------------------------------------------------------------------
--[[
	Podklad, který se nenahrával.

	Jedna nota = krátký vzorek přehraný ve správné výšce. Melodie je
	pak jen seznam stupňů pentatoniky, které se opakují dokola — a
	protože je pentatonika bez půltónů, nedá se rozladit ani při
	náhodném pořadí.

	Dvě vrstvy hrají proti sobě:
	  * `Bass`   — pomalý spodek, jedna nota na takt, drží tíhu
	  * `Melody` — rychlejší svršek, dává pohyb

	Zvlášť jsou proto, že se každá hodí na jiný vzorek: spodek potřebuje
	něco, co má dlouhý ocas (`SWIM` staženě), svršek naopak něco, co hned
	skončí (`STEP` vysoko).

	Tempo se liší podle světa — ne kvůli rozmanitosti, ale proto, že svět
	s rychlejším podkladem se hraje jinak než s pomalým, i když se v něm
	dělá totéž.
]]
Assets.Music = {
	Bass = { Id = SWIM, Volume = 0.16, Pitch = 0.42 },
	Melody = { Id = STEP, Volume = 0.09, Pitch = 2.1 },

	--[[
		Vzor melodie ve stupních pentatoniky (1..5) a nula jako pomlka.
		Pomlky jsou důležitější než noty: bez nich je z toho drnčení,
		s nimi to dýchá.
	]]
	Pattern = { 1, 0, 3, 0, 5, 4, 0, 3, 2, 0, 4, 0, 1, 0, 2, 0 },
	-- Spodek jede na čtvrtinu tempa melodie
	BassPattern = { 1, 0, 0, 0, 4, 0, 0, 0, 5, 0, 0, 0, 3, 0, 0, 0 },
}

-- Sekund na jednu notu melodie. Nižší číslo = rychlejší svět.
Assets.MusicTempo = {
	Glass = 0.30,
	Jelly = 0.36,
	Ice = 0.26,
	Chocolate = 0.40,
	Neon = 0.22,
	Void = 0.34,
	-- Mlhovina se vleče, výheň bije, kvantum cvaká, zahrada dýchá
	Nebula = 0.44,
	Solar = 0.20,
	Quantum = 0.18,
	Infinity = 0.38,
	-- Útes teče, bouře se valí, kovárna buší, vrchol stojí
	Prism = 0.3,
	Cotton = 0.46,
	Obsidian = 0.16,
	Aurora = 0.5,
}

function Assets.tempo(worldId: string): number
	return Assets.MusicTempo[worldId] or 0.3
end

-- Zvukové zpracování podle světa -----------------------------------------------
--[[
	Tohle je ta nejlevnější cesta, jak z hrstky vzorků udělat šest různých
	materiálů: neměnit vzorek, ale to, co se s ním stane po cestě.

	Stejný krok proženeš přes ostrý ekvalizér a krátký dozvuk a zní jako
	sklo. Ten samý krok přes dolní propust, chorus a dlouhý dozvuk zní jako
	želé. Přes distortion a kompresi jako čokoládová deska. Reálné studio
	dělá přesně tohle a Roblox na to má hotové instance.

	Hodnoty:
	  Eq       — zisk v dB (-80 až 10) pro basy, středy a výšky
	  Reverb   — délka dozvuku a poměr mokrého k suchému signálu
	  Distortion — 0 až 1
	  Chorus/Flange/Tremolo — hloubka, mix a rychlost modulace
	  Pitch    — posun v oktávách (0.5 až 2)

	Efekt, který svět nepoužívá, se nemaže — jen se stáhne na nulu.
	Přepnutí světa je pak plynulé, protože se jen dojedou hodnoty.
]]
Assets.Dsp = {
	-- Sklo: ostré výšky, žádné basy, krátký jasný dozvuk
	Glass = {
		Eq = { Low = -22, Mid = -2, High = 8 },
		Reverb = { Decay = 1.4, Wet = -7, Dry = 0, Density = 0.9, Diffusion = 1 },
		Distortion = 0.04,
		Flange = { Depth = 0.1, Mix = 0.12, Rate = 0.4 },
		Pitch = 1,
	},
	-- Želé: uříznuté výšky, rozmáznutý chorus, mokrý dozvuk
	Jelly = {
		Eq = { Low = 4, Mid = 0, High = -20 },
		Reverb = { Decay = 2.2, Wet = -4, Dry = -1, Density = 0.6, Diffusion = 0.7 },
		Distortion = 0,
		Chorus = { Depth = 0.5, Mix = 0.45, Rate = 2.2 },
		Pitch = 1,
	},
	-- Led: skelné výšky, flanger dělá to "praskání", dlouhá stopa
	Ice = {
		Eq = { Low = -26, Mid = -4, High = 9 },
		Reverb = { Decay = 3.4, Wet = -5, Dry = 0, Density = 1, Diffusion = 1 },
		Distortion = 0.02,
		Flange = { Depth = 0.35, Mix = 0.3, Rate = 1.1 },
		Pitch = 1.05,
	},
	-- Čokoláda: samé basy, tvrdá komprese, špetka zkreslení
	Chocolate = {
		Eq = { Low = 9, Mid = -2, High = -26 },
		Reverb = { Decay = 0.9, Wet = -12, Dry = 0, Density = 0.4, Diffusion = 0.4 },
		Distortion = 0.22,
		Pitch = 0.85,
	},
	-- Neon: elektrické, tremolo dělá to blikání, hodně dozvuku
	Neon = {
		Eq = { Low = -12, Mid = 3, High = 6 },
		Reverb = { Decay = 4.5, Wet = -3, Dry = -2, Density = 1, Diffusion = 0.9 },
		Distortion = 0.14,
		Flange = { Depth = 0.5, Mix = 0.4, Rate = 3.5 },
		Tremolo = { Depth = 0.35, Duty = 0.5, Frequency = 7 },
		Pitch = 1.1,
	},
	-- Void: obří prostor, posun o oktávu dolů, temné a dunivé
	Void = {
		Eq = { Low = 8, Mid = -6, High = -8 },
		Reverb = { Decay = 12, Wet = 0, Dry = -6, Density = 1, Diffusion = 1 },
		Distortion = 0.3,
		Chorus = { Depth = 0.3, Mix = 0.25, Rate = 0.6 },
		Pitch = 0.6,
	},
	--[[
		Mlhovina: nekonečný prostor bez stěn. Skoro žádné basy a hodně
		rozmáznutý chorus — po Voidu, který dusí, musí být slyšet, že
		je najednou kam dýchat.
	]]
	Nebula = {
		Eq = { Low = -16, Mid = 0, High = 4 },
		Reverb = { Decay = 9, Wet = -2, Dry = -4, Density = 0.5, Diffusion = 1 },
		Distortion = 0,
		Chorus = { Depth = 0.7, Mix = 0.5, Rate = 0.9 },
		Pitch = 1.15,
	},
	-- Výheň: zkreslení až na hranu, sucho a žádný ocas
	Solar = {
		Eq = { Low = 6, Mid = 4, High = -10 },
		Reverb = { Decay = 0.6, Wet = -16, Dry = 0, Density = 0.3, Diffusion = 0.3 },
		Distortion = 0.45,
		Tremolo = { Depth = 0.2, Duty = 0.6, Frequency = 11 },
		Pitch = 0.9,
	},
	-- Kvantum: skoro jen výšky, krátký přesný dozvuk, žádné špíny
	Quantum = {
		Eq = { Low = -30, Mid = -4, High = 10 },
		Reverb = { Decay = 2.2, Wet = -6, Dry = 0, Density = 1, Diffusion = 1 },
		Distortion = 0,
		Flange = { Depth = 0.25, Mix = 0.3, Rate = 6 },
		Pitch = 1.3,
	},
	--[[
		Zahrada: velký, plný a čistý zvuk. Poslední svět nemá znít jako
		další materiál v řadě, ale jako místo, kam se došlo.
	]]
	Infinity = {
		Eq = { Low = 4, Mid = 2, High = 5 },
		Reverb = { Decay = 6.5, Wet = -3, Dry = -1, Density = 0.9, Diffusion = 1 },
		Distortion = 0.05,
		Chorus = { Depth = 0.4, Mix = 0.3, Rate = 1.4 },
		Pitch = 1,
	},
	-- Útes: všechno pod vodou, výšky uříznuté, dlouhý mokrý dozvuk
	Prism = {
		Eq = { Low = 2, Mid = -1, High = -4 },
		Reverb = { Decay = 7, Wet = 1, Dry = -4, Density = 1, Diffusion = 1 },
		Chorus = { Depth = 0.5, Mix = 0.4, Rate = 0.8 },
		Pitch = 1.05,
	},
	-- Vata: dusí to. Skoro žádné výšky a skoro žádný dozvuk
	Cotton = {
		Eq = { Low = 3, Mid = 0, High = -8 },
		Reverb = { Decay = 1.2, Wet = -6, Dry = 0, Density = 0.4, Diffusion = 0.5 },
		Pitch = 0.95,
	},
	-- Kovárna: zkreslení a kovový sál
	Obsidian = {
		Eq = { Low = 6, Mid = 3, High = 1 },
		Reverb = { Decay = 4.5, Wet = -2, Dry = -1, Density = 0.8, Diffusion = 0.7 },
		Distortion = 0.35,
		Pitch = 0.8,
	},
	-- Vrchol: čistý vzduch a obrovský prostor, nic navíc
	Aurora = {
		Eq = { Low = 1, Mid = 2, High = 6 },
		Reverb = { Decay = 9, Wet = -2, Dry = -2, Density = 1, Diffusion = 1 },
		Pitch = 1.15,
	},
}

--[[
	Ambientní podklad. Není to hudba — je to jeden vzorek stažený hluboko
	dolů a puštěný ve smyčce přes ten samý dozvuk jako zbytek světa.
	Vznikne z toho tón, který drží atmosféru a nepotřebuje nic nahrávat.
]]
Assets.Ambience = {
	Id = WHOOSH,
	Volume = 0.12,
	Pitch = 0.18,
}

function Assets.dsp(worldId: string)
	return Assets.Dsp[worldId] or Assets.Dsp.Glass
end

--[[
	Textury.

	Prázdný řetězec = žádná textura, díl použije jen svůj materiál a barvu.
	Hra tak vypadá dobře i bez jediného nahraného obrázku. Až budeš mít
	vlastní, stačí sem doplnit ID a `Textures.luau` je začne posouvat
	(scrollovat) samo — animace textur je čistě v kódu.
]]
--[[
	Volitelné nahrané textury.

	Prázdné jméno znamená "žádná" a hra pak kreslí všechno procedurálně.
	Zůstala tu jen bariéra: podlaha i stěny se skládají z desítek
	samostatných dílů a posouvat texturu na každém z nich by nedávalo
	smysl — role `Floor` a `Wall` tu ležely od začátku a nikdo je nikdy
	nepřečetl.
]]
Assets.Textures = {
	-- Textura na bariéře, posouvá se nahoru jako energetické pole
	Barrier = "",
}

--[[
	Obrázky částic.

	Do teď neměl žádný emitter nastavenou `Texture`, takže všechno —
	střepy ze zdi, prach pod nohama, stopy za postavou i konfety
	z milníku — používalo tu samou výchozí jiskřičku. Deset různých
	efektů, které vypadají stejně, splyne v jeden.

	Jsou to soubory zabalené v každém klientu (`rbxasset://`), stejně
	jako zvuky výš: nic se nenahrává, nikomu nepatří a nepotřebují
	žádná práva.

	Prázdná hodnota znamená "nechat výchozí jiskřičku". Kdyby se cesta
	v nějaké verzi klienta přestala nacházet, efekt zmizí — proto se
	nikde nenastavuje natvrdo, ale přes `Assets.particle`.
]]
Assets.Particles = {
	Spark = "rbxasset://textures/particles/sparkles_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
}

--[[
	Nastaví emitteru obrázek, pokud nějaký známe.

	Přes funkci proto, že "prázdné = výchozí" musí platit na jednom
	místě; deset `if` u deseti emitterů se dřív nebo později rozejde.
]]
function Assets.particle(emitter: ParticleEmitter, name: string)
	local texture = Assets.Particles[name]
	if texture and texture ~= "" then
		emitter.Texture = texture
	end
end

--[[
	Vrátí recept pro průraz v daném světě. Když má hráč v `Override`
	vlastní zvuk, recept se nahradí jednou vrstvou s ním — vlastní ASMR
	nahrávka nepotřebuje skládání z kroků.
]]
function Assets.smashRecipe(worldId: string): Recipe
	local override = Assets.Override[`Smash_{worldId}`]
	if override then
		return { { Id = override, Pitch = 1, Volume = 0.9 } }
	end
	return Assets.Smash[worldId] or Assets.Smash.Glass
end

function Assets.recipe(name: string): Recipe?
	local override = Assets.Override[name]
	if override then
		return { { Id = override, Pitch = 1, Volume = 0.5 } }
	end
	return Assets.Recipes[name]
end

return Assets

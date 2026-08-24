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
	-- Dopad po skoku (doplňuje vestavěný zvuk o měkčí ocas)
	Land = {
		{ Id = STEP, Pitch = 0.9, Volume = 0.2 },
	},
}

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
Assets.Textures = {
	-- Textura na bariéře, posouvá se nahoru jako energetické pole
	Barrier = "",
	-- Textura podlahy, posouvá se směrem k hráči
	Floor = "",
	-- Textura pruhů na stěnách
	Wall = "",
}

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

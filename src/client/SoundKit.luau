--!strict
--[[
	SoundKit — vrstvený přehrávač zvuků.

	Jádro ASMR pocitu není jeden dokonalý sample, ale několik vrstev
	s posunutou výškou a zpožděním o setiny sekundy. Tenhle modul umí
	přehrát celý recept z `Assets` jako jeden zvuk.

	Dvě věci, které dělají výsledek "satisfying":
	  * `Sequence` — při rychlém sbírání stoupá výška tónu jako stupnice
	    a po pauze spadne zpátky. Tohle je ten návykový prvek.
	  * lehká náhoda ve výšce každé vrstvy, aby dvě rány nezněly identicky.

	Zvuky se recyklují z poolu; nová instance na každý pickup by při
	desítkách sebrání za sekundu jen zbytečně zatěžovala GC.
]]

local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Assets = require(Shared.Assets)

local SoundKit = {}

local random = Random.new()

--[[
	Tři skupiny, ne jedna.

	  Material — nárazy a materiály. Jede přes celý DSP řetězec, takže
	             se dá tvarovat podle světa.
	  Ui       — kliky a potvrzení. Bez efektů: reverb na tlačítku
	             zní jako chyba, ne jako atmosféra.
	  Ambience — podkladový tón. Odděleně, aby šel při průrazu stáhnout.
]]
local group = Instance.new("SoundGroup")
group.Name = "Material"
group.Volume = 1
group.Parent = SoundService

local uiGroup = Instance.new("SoundGroup")
uiGroup.Name = "Ui"
uiGroup.Volume = 1
uiGroup.Parent = SoundService

local ambienceGroup = Instance.new("SoundGroup")
ambienceGroup.Name = "Ambience"
ambienceGroup.Volume = 1
ambienceGroup.Parent = SoundService

--[[
	Hudba má vlastní skupinu, ne Ambience.

	Podklad se při každém průrazu stahuje (ducking) a to je u dronu
	správně — u hudby by z toho bylo cukání v rytmu, který nesouvisí
	s tím jejím. Zvlášť taky proto, že hudba jde vypnout samostatně.
]]
local musicGroup = Instance.new("SoundGroup")
musicGroup.Name = "Music"
musicGroup.Volume = 1
musicGroup.Parent = SoundService

-- Řetězec efektů. Vytvoří se jednou a pak se jen dojíždí jeho hodnoty —
-- přidávat a mazat instance při každé změně světa by cvakalo.
local function makeEffect(className: string, name: string): any
	local effect = Instance.new(className)
	effect.Name = name
	effect.Parent = group
	return effect
end

local eq = makeEffect("EqualizerSoundEffect", "Eq")
local reverb = makeEffect("ReverbSoundEffect", "Reverb")
local distortion = makeEffect("DistortionSoundEffect", "Distortion")
local chorus = makeEffect("ChorusSoundEffect", "Chorus")
local flange = makeEffect("FlangeSoundEffect", "Flange")
local tremolo = makeEffect("TremoloSoundEffect", "Tremolo")
local pitch = makeEffect("PitchShiftSoundEffect", "Pitch")

local compressor = makeEffect("CompressorSoundEffect", "Compressor")
compressor.Threshold = -14
compressor.Ratio = 4
compressor.Attack = 0.01
compressor.Release = 0.14
compressor.GainMakeup = 3

local pool: { Sound } = {}
local POOL_LIMIT = 40

local function acquire(): Sound
	local sound = table.remove(pool)
	if sound then
		return sound
	end

	local created = Instance.new("Sound")
	created.RollOffMode = Enum.RollOffMode.InverseTapered
	created.RollOffMaxDistance = 140
	return created
end

local function release(sound: Sound)
	sound:Stop()
	sound.Parent = nil

	if #pool < POOL_LIMIT then
		table.insert(pool, sound)
	else
		sound:Destroy()
	end
end

-- Přechod mezi světy trvá skoro sekundu, aby se zvuk nepřepnul skokem
local TRANSITION = TweenInfo.new(0.9, Enum.EasingStyle.Quad)

local function tween(instance: Instance, properties: { [string]: any })
	TweenService:Create(instance, TRANSITION, properties):Play()
end

--[[
	Nastaví DSP podle světa. Efekt, který profil nezmiňuje, se stáhne
	na nulu místo smazání — dojezd je pak plynulý.
]]
function SoundKit.setWorld(worldId: string)
	local profile = Assets.dsp(worldId)

	tween(eq, {
		LowGain = math.clamp(profile.Eq.Low, -80, 10),
		MidGain = math.clamp(profile.Eq.Mid, -80, 10),
		HighGain = math.clamp(profile.Eq.High, -80, 10),
	})

	tween(reverb, {
		DecayTime = math.clamp(profile.Reverb.Decay, 0.1, 20),
		WetLevel = math.clamp(profile.Reverb.Wet, -80, 10),
		DryLevel = math.clamp(profile.Reverb.Dry, -80, 10),
		Density = math.clamp(profile.Reverb.Density, 0, 1),
		Diffusion = math.clamp(profile.Reverb.Diffusion, 0, 1),
	})

	tween(distortion, { Level = math.clamp(profile.Distortion or 0, 0, 1) })
	tween(pitch, { Octave = math.clamp(profile.Pitch or 1, 0.5, 2) })

	local chorusProfile = profile.Chorus
	tween(chorus, {
		Depth = if chorusProfile then math.clamp(chorusProfile.Depth, 0, 1) else 0,
		Mix = if chorusProfile then math.clamp(chorusProfile.Mix, 0, 1) else 0,
		Rate = if chorusProfile then math.clamp(chorusProfile.Rate, 0, 20) else 1,
	})

	local flangeProfile = profile.Flange
	tween(flange, {
		Depth = if flangeProfile then math.clamp(flangeProfile.Depth, 0, 1) else 0,
		Mix = if flangeProfile then math.clamp(flangeProfile.Mix, 0, 1) else 0,
		Rate = if flangeProfile then math.clamp(flangeProfile.Rate, 0, 20) else 1,
	})

	local tremoloProfile = profile.Tremolo
	tween(tremolo, {
		Depth = if tremoloProfile then math.clamp(tremoloProfile.Depth, 0, 1) else 0,
		Duty = if tremoloProfile then math.clamp(tremoloProfile.Duty, 0, 1) else 0.5,
		Frequency = if tremoloProfile then math.clamp(tremoloProfile.Frequency, 0, 20) else 5,
	})

	SoundKit.setAmbience(worldId)
	-- Tempo podkladu podle světa: stejná činnost se v jiném tempu hraje jinak
	musicTempo = Assets.tempo(worldId)
end

-- Ambientní podklad ---------------------------------------------------------------

local ambience: Sound? = nil
-- Vypnutý zvuk musí přežít i změnu světa, jinak ho `setAmbience` zapne zpátky
local soundEnabled = true

--[[
	Jeden vzorek stažený hluboko a puštěný ve smyčce. Prochází stejným
	dozvukem jako zbytek světa, takže se z něj stane tón, který drží
	atmosféru — a nemuselo se kvůli tomu nic nahrávat.
]]
function SoundKit.setAmbience(worldId: string)
	if not ambience then
		local sound = Instance.new("Sound")
		sound.Name = "Ambience"
		sound.SoundId = Assets.Ambience.Id
		sound.Looped = true
		sound.Volume = 0
		sound.SoundGroup = ambienceGroup
		sound.Parent = SoundService

		if not pcall(function()
			sound:Play()
		end) then
			sound:Destroy()
			return
		end

		ambience = sound
	end

	local profile = Assets.dsp(worldId)
	local sound = ambience :: Sound
	tween(sound, {
		Volume = if soundEnabled then Assets.Ambience.Volume else 0,
		PlaybackSpeed = Assets.Ambience.Pitch * (profile.Pitch or 1),
	})
end

-- Hudba ---------------------------------------------------------------------------

--[[
	Procedurální podklad.

	Žádná nahrávka: nota je krátký vzorek přehraný ve správné výšce,
	melodie je seznam stupňů pentatoniky. Bez půltónů se to nedá
	rozladit, takže i vzor, který nikdo nesložil, zní jako hudba.

	Smyčka je jedna a jede pořád — i s vypnutou hudbou. Vypnutí jen
	stáhne hlasitost skupiny na nulu. Zastavovat a spouštět smyčku by
	znamenalo řešit, kde se má po zapnutí navázat, a hlavně by se
	rytmus rozešel se světem.
]]
-- Durová pentatonika: bez půltónů, takže se nedá rozladit ani náhodným
-- pořadím. Používá ji stoupající stupnice u pickupů i hudba.
local PENTATONIC = { 1, 9 / 8, 5 / 4, 3 / 2, 5 / 3, 2 }

local musicEnabled = true
local musicStep = 0
local musicTempo = 0.3
local musicSwell = 0

--[[
	Jedna nota. `degree` je stupeň pentatoniky (1..#PENTATONIC), nula
	je pomlka — ta se sem vůbec nedostane, filtruje ji smyčka.
]]
local function playNote(layer, degree: number, octave: number)
	local sound = Instance.new("Sound")
	sound.SoundId = layer.Id
	sound.Volume = layer.Volume * (0.65 + musicSwell * 0.35)
	sound.PlaybackSpeed = layer.Pitch * PENTATONIC[degree] * (2 ^ octave)
	sound.SoundGroup = musicGroup
	sound.Parent = SoundService

	if not pcall(function()
		sound:Play()
	end) then
		sound:Destroy()
		return
	end

	Debris:AddItem(sound, 4)
end

--[[
	Zapnutí a vypnutí hudby. Nemění smyčku, jen hlasitost skupiny —
	viz komentář výš.
]]
function SoundKit.setMusic(enabled: boolean)
	musicEnabled = enabled
	TweenService:Create(musicGroup, TweenInfo.new(0.6), {
		Volume = if enabled then 1 else 0,
	}):Play()
end

--[[
	Nabuzení podkladu podle comba (0..1). Hudba tím reaguje na to, jak
	se hráči daří — je to ta nejlevnější cesta, jak dát rozjetému combu
	zvukovou váhu, aniž by se přidal další zvuk navrch.
]]
function SoundKit.setMusicSwell(amount: number)
	musicSwell = math.clamp(amount, 0, 1)
end

function SoundKit.startMusic()
	task.spawn(function()
		local music = Assets.Music

		while true do
			task.wait(musicTempo)

			musicStep += 1

			--[[
				Krok se počítá i s vypnutou hudbou, ale noty se nevyrábějí.
				Rytmus tak po zapnutí navazuje tam, kde by byl — a mezitím
				se nevytváří šestnáct tichých zvuků za takt.
			]]
			if not musicEnabled then
				continue
			end

			local index = (musicStep - 1) % #music.Pattern + 1

			local melody = music.Pattern[index]
			if melody > 0 then
				playNote(music.Melody, melody, 0)
			end

			local bass = music.BassPattern[index]
			if bass > 0 then
				-- Spodek o oktávu níž, aby se se svrškem nepral
				playNote(music.Bass, bass, -1)
			end
		end
	end)
end

--[[
	Ducking: při průrazu se podklad na okamžik stáhne a hned se vrátí.
	Je to ten samý trik, co dělá sidechain v hudbě — náraz tím dostane
	prostor a zní o dost tvrději, aniž by se musel zesilovat.
]]
function SoundKit.duck(amount: number, holdSeconds: number)
	local target = math.clamp(1 - amount, 0, 1)

	TweenService:Create(ambienceGroup, TweenInfo.new(0.05), { Volume = target }):Play()
	task.delay(holdSeconds, function()
		TweenService:Create(ambienceGroup, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {
			Volume = 1,
		}):Play()
	end)
end

--[[
	Jedna vrstva. `parent` určuje, jestli zvuk zní z místa (díl ve světě)
	nebo plošně (SoundService). Nepřehratelné ID se tiše přeskočí —
	chybějící zvuk nikdy nesmí shodit hru ani zaplavit konzoli chybami.
]]
local function playLayer(
	layer: Assets.Layer,
	parent: Instance,
	volumeScale: number,
	pitchScale: number,
	soundGroup: SoundGroup
)
	local sound = acquire()
	sound.SoundGroup = soundGroup
	sound.SoundId = layer.Id
	sound.PlaybackSpeed = layer.Pitch * pitchScale * random:NextNumber(0.97, 1.03)
	sound.Volume = layer.Volume * volumeScale
	sound.Parent = parent

	if not pcall(function()
		sound:Play()
	end) then
		release(sound)
		return
	end

	--[[
		Ohyb výšky. Sklouznutí dolů zní jako mokré stlačení, nahoru jako
		odskok — viz `Assets.Layer.Bend`.

		Jede se tweenem, ne po snímcích: tween běží na straně enginu, takže
		desítka najednou znějících vrstev nestojí nic navíc, a hlavně se
		nerozejde s hudbou, když klientu klesne snímková frekvence.
	]]
	if layer.Bend then
		local info = TweenInfo.new(layer.BendTime or 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(sound, info, {
			PlaybackSpeed = layer.Bend * pitchScale,
		}):Play()
	end

	task.delay(4, release, sound)
end

--[[
	Přehraje celý recept.

	`position` nepovinná: když je zadaná, zvuk se přehraje z toho místa
	ve světě (a ostatní hráči poblíž ho slyší tišeji podle vzdálenosti).
]]
function SoundKit.play(recipe: Assets.Recipe?, options: {
	Position: Vector3?,
	Volume: number?,
	Pitch: number?,
	Group: SoundGroup?,
}?)
	if not recipe then
		return
	end

	local opts = options or {}
	local volumeScale = opts.Volume or 1
	local pitchScale = opts.Pitch or 1

	local parent: Instance = SoundService
	if opts.Position then
		-- Attachment stačí na prostorový zvuk a je mnohem levnější než díl.
		-- Žije o sekundu dýl než zvuk sám, aby ho nezničil dřív, než dohraje.
		local anchor = Instance.new("Attachment")
		anchor.Name = "SoundAnchor"
		anchor.WorldPosition = opts.Position
		anchor.Parent = workspace.Terrain
		Debris:AddItem(anchor, 5)
		parent = anchor
	end

	local soundGroup = opts.Group or group

	for _, layer in recipe do
		if layer.Delay and layer.Delay > 0 then
			task.delay(layer.Delay, playLayer, layer, parent, volumeScale, pitchScale, soundGroup)
		else
			playLayer(layer, parent, volumeScale, pitchScale, soundGroup)
		end
	end
end

-- Vypnutí přes nastavení. Ztlumí se celá skupina, takže se nemusí
-- kontrolovat u každého jednotlivého přehrání.
function SoundKit.setEnabled(enabled: boolean)
	soundEnabled = enabled
	local volume = if enabled then 1 else 0
	group.Volume = volume
	uiGroup.Volume = volume
	if ambience then
		(ambience :: Sound).Volume = if enabled then Assets.Ambience.Volume else 0
	end
end

-- Zvuky rozhraní jdou mimo DSP: dozvuk na kliknutí zní jako chyba
local UI_SOUNDS = { Click = true, Purchase = true }

--[[
	Výška podle zóny.

	Terén se pod hráčem mění (viz `Shared.Zones`) a musí to být slyšet,
	ne jen vidět. Nová nahrávka na to není potřeba: stejný vzorek výš
	zní tvrději (sklo, kov), níž měkčeji (pěna, void).

	Násobí se jen zvuky ze světa — krok, dopad, pickup. Kliky v menu ne:
	tlačítko, které cvakne jinak podle toho, kde hráč stojí, působí
	rozbitě.
]]
local zonePitch = 1
local zoneSound = "Glass"

function SoundKit.setZone(soundId: string, pitch: number)
	zoneSound = soundId
	zonePitch = math.clamp(pitch, 0.4, 3)
end

--[[
	Zvuk terénu, na kterém hráč zrovna stojí. Krok a dopad chodí tudy,
	takže se materiál pod nohama ozve sám od sebe, aniž by o zónách
	musel vědět ten, kdo zvuk spouští.
]]
function SoundKit.playTerrain(kind: string, options: { Position: Vector3?, Volume: number? }?)
	local opts = options or {}
	SoundKit.play(Assets.terrain(zoneSound, kind), {
		Position = opts.Position,
		Volume = opts.Volume,
	})
end

function SoundKit.playNamed(name: string, options: { Position: Vector3?, Volume: number?, Pitch: number? }?)
	local opts = options or {}
	local ui = UI_SOUNDS[name] == true

	SoundKit.play(Assets.recipe(name), {
		Position = opts.Position,
		Volume = opts.Volume,
		Pitch = (opts.Pitch or 1) * (if ui then 1 else zonePitch),
		Group = if ui then uiGroup else nil,
	})
end

-- Stoupající stupnice -------------------------------------------------------------

--[[
	Sequence drží tón, který stoupá s každým dalším sebráním v rychlém
	sledu a po pauze spadne zpátky na začátek. Stupnice je durová
	pentatonika — vždycky zní dobře, ať se hráč zastaví kdekoliv.
]]
local Sequence = {}
Sequence.__index = Sequence

export type Ladder = typeof(setmetatable({} :: any, Sequence))

function SoundKit.ladder(resetAfter: number): Ladder
	return setmetatable({
		Step = 0,
		LastAt = 0,
		ResetAfter = resetAfter,
	}, Sequence)
end

function Sequence:next(now: number): number
	if now - self.LastAt > self.ResetAfter then
		self.Step = 0
	end
	self.LastAt = now

	local octave = self.Step // #PENTATONIC
	local note = PENTATONIC[self.Step % #PENTATONIC + 1]

	self.Step += 1
	-- strop na dvou oktávách, výš už to zní jen pisklavě
	if self.Step >= #PENTATONIC * 2 then
		self.Step = #PENTATONIC
	end

	return note * 2 ^ math.min(octave, 1)
end

return SoundKit

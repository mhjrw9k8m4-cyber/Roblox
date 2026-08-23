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

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Assets = require(Shared.Assets)

local SoundKit = {}

local random = Random.new()

-- Vlastní skupina, aby si hráč mohl ztlumit efekty bez zbytku hry
local group = Instance.new("SoundGroup")
group.Name = "SFX"
group.Volume = 1
group.Parent = SoundService

local pool: { Sound } = {}
local POOL_LIMIT = 40

local function acquire(): Sound
	local sound = table.remove(pool)
	if sound then
		return sound
	end

	local created = Instance.new("Sound")
	created.SoundGroup = group
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

--[[
	Jedna vrstva. `parent` určuje, jestli zvuk zní z místa (díl ve světě)
	nebo plošně (SoundService). Nepřehratelné ID se tiše přeskočí —
	chybějící zvuk nikdy nesmí shodit hru ani zaplavit konzoli chybami.
]]
local function playLayer(layer: Assets.Layer, parent: Instance, volumeScale: number, pitchScale: number)
	local sound = acquire()
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

	for _, layer in recipe do
		if layer.Delay and layer.Delay > 0 then
			task.delay(layer.Delay, playLayer, layer, parent, volumeScale, pitchScale)
		else
			playLayer(layer, parent, volumeScale, pitchScale)
		end
	end
end

function SoundKit.playNamed(name: string, options: { Position: Vector3?, Volume: number?, Pitch: number? }?)
	SoundKit.play(Assets.recipe(name), options)
end

-- Stoupající stupnice -------------------------------------------------------------

--[[
	Sequence drží tón, který stoupá s každým dalším sebráním v rychlém
	sledu a po pauze spadne zpátky na začátek. Stupnice je durová
	pentatonika — vždycky zní dobře, ať se hráč zastaví kdekoliv.
]]
local PENTATONIC = { 1, 9 / 8, 5 / 4, 3 / 2, 5 / 3, 2 }

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

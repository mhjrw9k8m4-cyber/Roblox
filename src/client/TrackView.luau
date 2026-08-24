--!strict
--[[
	TrackView — pickupy a prorazitelné tabule, stavěné lokálně.

	Proč lokálně: bariéra musí blokovat každého hráče podle jeho vlastního
	postupu a sebraný pickup musí zmizet jen tomu, kdo ho sebral. Sdílená
	geometrie by to neuměla — díl vytvořený na klientovi existuje jen u něj,
	takže jeho fyzika i viditelnost jsou automaticky "per hráč".

	Server na to samozřejmě nespoléhá: každý sebraný pickup i každý průraz
	si znovu ověří podle vlastních čísel (viz GameService).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Build = require(Shared.Build)
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Patterns = require(Shared.Patterns)
local Track = require(Shared.Track)
local Zones = require(Shared.Zones)

local CharacterFX = require(script.Parent.CharacterFX)
local Effects = require(script.Parent.Effects)
local Fracture = require(script.Parent.Fracture)
local SoundKit = require(script.Parent.SoundKit)
local Squish = require(script.Parent.Squish)
local Textures = require(script.Parent.Textures)

local TRACK = Config.Track
local player = Players.LocalPlayer

local TrackView = {}
TrackView.__index = TrackView

export type Handle = typeof(setmetatable({} :: any, TrackView))

type Pickup = {
	Index: number,
	Part: BasePart,
	Position: Vector3,
	ReadyAt: number,
	-- Kdy se pickup začal nafukovat zpátky; houpání do té doby čeká
	RoseAt: number?,
	Golden: boolean?,
	-- Když je nastaveno, pickup právě letí k hráči
	Flying: number?,
	FlyFrom: Vector3?,
	--[[
		Tvar se liší podle zóny, takže velikost ani natočení nesmí být
		v animaci natvrdo. Kdyby byly, kolečko másla by se po sebrání
		vrátilo jako kostka.
	]]
	BaseSize: Vector3,
	Tilt: CFrame,
	--[[
		Lokální osa, do které se pickup mačká. U kostky je to Y, jenže
		válec má v Robloxu osu ve směru X a je otočený na plocho — jeho
		"dolů" je tedy lokální X. Bez tohohle by se kolečko másla mačkalo
		do boku a vypadalo by, že se přetáčí.
	]]
	PressAxis: Vector3,
	--[[
		Otáčí se? Koule vypadá při otáčení úplně stejně jako bez něj,
		takže se u ní jen houpe — ušetřený zápis do CFrame u stovky dílů
		každý snímek není nic, co by šlo zanedbat.
	]]
	Spin: boolean,
}

type Barrier = {
	Index: number,
	Part: BasePart,
	Label: TextLabel,
	Required: number,
	-- Kolik prasklin už je vidět; roste s nabitím
	Cracks: number,
	CrackParts: { BasePart },
}

function TrackView.new(): Handle
	local self = setmetatable({}, TrackView)

	self.Folder = nil :: Folder?
	self.Pickups = {} :: { [number]: Pickup }
	self.Barriers = {} :: { [number]: Barrier }
	self.WorldIndex = 0
	self.World = Config.Worlds[1]
	self.Power = 0
	self.Barrier = 1
	self.PickupValue = 1
	self.CollectRadius = TRACK.CollectRadius

	self.WasReady = false
	self.PendingCollects = {} :: { number }
	self.LastSendAt = 0
	self.LastSmashAt = 0
	self.LastBlockedAt = 0

	return self
end

-- Stavba -----------------------------------------------------------------------

--[[
	Tvar a barva drobnosti podle zóny.

	Pickup je to, na co se hráč při běhu dívá nejvíc. Když má přes celou
	trať jeden tvar a jednu barvu, splyne mu to v nekonečný pás a postup
	přestane být vidět přesně tam, kde se dívá.

	Kolečko (Butter Block) potřebuje navíc natočení: válec má v Robloxu
	osu ve směru X, takže bez otočení by ležel jako klacek napříč tratí,
	ne jako mince.
]]
local function pickupLook(zone): (Vector3, CFrame, Color3, Vector3)
	if zone.Pickup.Shape == "Cylinder" then
		return Vector3.new(0.9, 2.8, 2.8),
			CFrame.Angles(0, 0, math.rad(90)),
			zone.Pickup.Color,
			-Vector3.xAxis
	end

	return Vector3.new(2.4, 2.4, 2.4), CFrame.identity, zone.Pickup.Color, -Vector3.yAxis
end

--[[
	Zlatý pickup musí být vidět **z dálky**, jinak není co objevovat —
	hráč by na něj náhodou šlápl a nevšiml si toho. Proto je větší,
	svítí vlastním světlem a má sloupec nahoru, který je vidět i přes
	ostatní pickupy.

	Zlatý se zóně schválně nepřizpůsobuje: jeho jediný úkol je vyčnívat.
]]
local function makePickup(zone, position: Vector3, golden: boolean, parent: Instance): BasePart
	local size, tilt, color = pickupLook(zone)

	local part = Build.part({
		Name = if golden then "GoldenPickup" else "Pickup",
		Shape = if golden
			then Enum.PartType.Block
			else (Enum.PartType :: any)[zone.Pickup.Shape] or Enum.PartType.Block,
		Size = if golden then Vector3.new(3.6, 3.6, 3.6) else size,
		Position = position,
		Color = if golden then Config.Theme.Gold else color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
		Parent = parent,
	})

	if not golden then
		part.CFrame = CFrame.new(position) * tilt
	end

	Build.billboard({
		Adornee = part,
		Text = if golden then `<b>+{Config.Track.GoldenValue}</b>` else "<b>+1</b>",
		Size = if golden then UDim2.fromScale(6, 2.4) else UDim2.fromScale(4, 1.6),
		Offset = Vector3.new(0, if golden then 3.4 else 2.4, 0),
		Color = if golden then Config.Theme.Gold else Config.Theme.Text,
		MaxDistance = if golden then 320 else 90,
	})

	if golden then
		Build.light(part, Config.Theme.Gold, 2.4, 22)

		-- Světelný sloupec: jediné, co je vidět přes hlavy ostatních pickupů
		local beacon = Build.part({
			Name = "Maják",
			Size = Vector3.new(0.7, 26, 0.7),
			Position = position + Vector3.new(0, 13, 0),
			Color = Config.Theme.Gold,
			Material = Enum.Material.Neon,
			Transparency = 0.72,
			CanCollide = false,
			CastShadow = false,
			Parent = part,
		})
		beacon.Name = "Maják"
	end

	return part
end

local function makeBarrier(
	world,
	worldIndex: number,
	index: number,
	parent: Instance,
	chargeOf: (number) -> number
): (BasePart, TextLabel)
	local position = Track.barrierPosition(worldIndex, index)

	--[[
		Zeď nese materiál **zóny**, ne světa. Hráč tak neproráží dvanáctkrát
		to samé: v želé je zeď sklo, v marshmallow písek, ve voidu silové
		pole. Barva zůstává světu, aby bylo pořád poznat, kde jsi.
	]]
	local zone = Zones.at(index)
	local material = (Enum.Material :: any)[zone.WallMaterial] or world.Material

	--[[
		Zeď přes CELOU chodbu, od podlahy až ke stropu oblouku.

		Dřív to byla tabule uprostřed průchodu — vypadala jako dveře,
		kolem kterých se dá projít. Zeď, která se nedá obejít ani
		přeskočit, je jediné, co dá průrazu váhu.
	]]
	local part = Build.part({
		Name = `Barrier{index}`,
		Size = Vector3.new(TRACK.Width, 28, 3.2),
		Position = position + Vector3.new(0, 8, 0),
		Color = world.Color:Lerp(zone.Edge, 0.35),
		Material = material,
		Transparency = 0.25,
		CanCollide = true,
		CastShadow = false,
		Parent = parent,
	})

	-- Proudící energie napříč tabulí. Beam nepotřebuje obrázek, takže
	-- tohle funguje i bez jediného nahraného assetu.
	Textures.energyField(part, world, 7)

	-- Volitelná textura navrch, když si ji hráč doplní do Assets
	Textures.scroll(part, Enum.NormalId.Front, {
		Asset = Textures.assetFor("Barrier"),
		Color = world.Accent,
		StudsPerTile = 6,
		SpeedV = 4,
		Transparency = 0.35,
	})

	--[[
		Buněčná mřížka na čelní straně. Plní se zdola podle nabití,
		takže postup je vidět na zdi samotné a hráč kvůli němu nemusí
		koukat do UI. Rozměr 9×7 vychází z poměru zdi — víc buněk
		by na dálku splynulo v šum.
	]]
	Textures.cellGrid(part, world, 9, 7, function()
		return chargeOf(index)
	end)

	-- Pulz zrychluje, jak se hráč blíží k proražení
	Textures.charge(part, world.Color, world.Accent, function()
		return 3 + chargeOf(index) * 14
	end)

	local _, label = Build.billboard({
		Adornee = part,
		Text = "",
		Size = UDim2.fromScale(18, 5),
		Offset = Vector3.new(0, 18, 0),
		Color = Config.Theme.Text,
		AlwaysOnTop = true,
		MaxDistance = 320,
	})

	return part, label
end

--[[
	Squishy dlaždice pod nohama.

	V žánru se teď dělají pásy, po kterých se chodí pro bonus. Tohle je
	ta samá myšlenka posunutá jinam: chodíš po **squishy blocích** a ty
	se pod tebou promáčknou a pomalu vrací. Bonus není v číslech, ale
	v tom, že se svět pod nohama hýbe.

	Dlaždice nejsou po celé trati — bylo by jich přes tisíc. Staví se jen
	pro úsek, ve kterém hráč zrovna je, a pro dva před ním, a přestavují
	se, až se posune dál. Zbytek trati nese plná podlaha ze serveru, takže
	pod hráčem nikdy nechybí zem.

	Kolizi dlaždice nemají schválně: hráč stojí na podlaze pod nimi.
	Kdyby na nich stál, propadal by se s nimi a chůze by se rozhoupala.
]]
local TILE_COLUMNS = 8
local TILE_ROWS = 10
-- Kolik úseků dopředu se dláždí; víc už hráč stejně nevidí
local TILE_SEGMENTS = 3

function TrackView:buildTiles(fromSegment: number)
	self:clearTiles()

	local zone = Zones.at(math.clamp(fromSegment + 1, 1, TRACK.BarrierCount))
	local origin = Track.origin(self.WorldIndex)
	local width = TRACK.Width / TILE_COLUMNS
	local depth = TRACK.SegmentLength / TILE_ROWS

	local folder = Instance.new("Folder")
	folder.Name = "Dlaždice"
	folder.Parent = self.Folder

	local tiles = {}

	for segment = 0, TILE_SEGMENTS - 1 do
		local baseZ = (fromSegment + segment) * TRACK.SegmentLength

		for row = 0, TILE_ROWS - 1 do
			--[[
				Řada se počítá od začátku TRATĚ, ne od začátku dlážděného
				kusu. Bez toho by se vzor při každé přestavbě posunul
				a podlaha by pod hráčem "poskočila".
			]]
			local globalRow = (fromSegment + segment) * TILE_ROWS + row

			for column = 0, TILE_COLUMNS - 1 do
				local tile = Build.part({
					Name = "Dlaždice",
					Size = Vector3.new(width * 0.9, 1.2, depth * 0.9),
					Position = origin
						+ Vector3.new(
							(column - (TILE_COLUMNS - 1) / 2) * width,
							0.6,
							baseZ + row * depth - TRACK.SegmentLength / 2
						),
					--[[
						Barva z procedurálního vzoru zóny (viz `Shared.Patterns`).
						Zóna se tím liší nejen odstínem, ale i kresbou —
						posypka, spáry, pruhy — a to je vidět i na dálku,
						kdežto dva odstíny téže barvy splynou.
					]]
					Color = Patterns.tile(zone.Pattern, column, globalRow, {
						Base = zone.Floor,
						Accent = zone.Edge,
						Extra = self.World.Accent,
					}),
					Material = Enum.Material.SmoothPlastic,
					Reflectance = zone.Reflectance,
					CanCollide = false,
					CastShadow = false,
					Parent = folder,
				})

				table.insert(tiles, tile)
			end
		end
	end

	self.Tiles = tiles
	self.TileFolder = folder
	self.TileFrom = fromSegment
end

function TrackView:clearTiles()
	for _, tile in self.Tiles or {} do
		Squish.release(tile)
	end

	if self.TileFolder then
		self.TileFolder:Destroy()
	end

	self.Tiles = nil
	self.TileFolder = nil
	self.TileFrom = nil
end

--[[
	Promáčkne dlaždice pod hráčem.

	Volá se každý snímek, ale `Squish.press` na už zmáčknutou dlaždici jen
	prodlouží návrat — takže z běhu vznikne souvislá stopa důlků, ne
	blikání.
]]
function TrackView:pressTiles(position: Vector3)
	local tiles = self.Tiles
	if not tiles then
		return
	end

	for _, tile in tiles do
		local flat = (tile.Position - position) * Vector3.new(1, 0, 1)
		local falloff = 1 - math.clamp(flat.Magnitude / 7, 0, 1)
		if falloff <= 0.05 then
			continue
		end

		Squish.press(tile, 0.7 * falloff, 0.9 + falloff * 1.3)
	end
end

--[[
	Měkký povrch aktivní zdi.

	Zeď je jeden díl a díl se lokálně promáčknout nedá. Na její čelo se
	proto pověsí mřížka tenkých bloků — a ty už se mačkat dají, každý
	zvlášť. Když do zdi vrazíš, propadnou se ty kolem tebe a pomalu se
	vrátí, přesně jako důlek po prstu ve squishy hračce.

	Staví se jen pro tu jednu zeď, kterou hráč zrovna vidí. Dvanáct
	mřížek naráz by bylo tři sta dílů navíc za něco, co stejně není vidět.
]]
local SKIN_COLUMNS = 7
local SKIN_ROWS = 5

function TrackView:buildSoftSkin(barrier)
	self:clearSoftSkin()

	local part = barrier.Part
	local zone = Zones.at(barrier.Index)

	local width = part.Size.X / SKIN_COLUMNS
	local height = part.Size.Y / SKIN_ROWS
	local blocks = {}

	for row = 0, SKIN_ROWS - 1 do
		for column = 0, SKIN_COLUMNS - 1 do
			local offset = Vector3.new(
				(column - (SKIN_COLUMNS - 1) / 2) * width,
				(row - (SKIN_ROWS - 1) / 2) * height,
				-- Kousek před čelem zdi, ať do ní bloky nezapadají
				-part.Size.Z / 2 - 0.35
			)

			local block = Build.part({
				Name = "Měkký blok",
				Size = Vector3.new(width * 0.92, height * 0.92, 0.7),
				CFrame = part.CFrame * CFrame.new(offset),
				Color = zone.Edge,
				Material = Enum.Material.SmoothPlastic,
				Transparency = 0.25,
				Reflectance = 0.25,
				CanCollide = false,
				CastShadow = false,
				Parent = part,
			})

			table.insert(blocks, block)
		end
	end

	self.SoftSkin = blocks
	self.SoftSkinFor = barrier.Index
end

function TrackView:clearSoftSkin()
	for _, block in self.SoftSkin or {} do
		Squish.release(block)
		block:Destroy()
	end

	self.SoftSkin = nil
	self.SoftSkinFor = nil
end

--[[
	Promáčkne bloky kolem místa, kam hráč do zdi vrazil.

	Hloubka klesá se vzdáleností od nárazu, takže vznikne důlek, ne
	rovnoměrné stlačení celé zdi. Návrat je schválně dlouhý — právě
	to zdržení je na squishy hračkách to uspokojivé.
]]
function TrackView:dentWall(worldPoint: Vector3, strength: number)
	local blocks = self.SoftSkin
	if not blocks then
		return
	end

	for _, block in blocks do
		local distance = (block.Position - worldPoint).Magnitude
		local falloff = 1 - math.clamp(distance / 14, 0, 1)
		if falloff <= 0.02 then
			continue
		end

		Squish.press(
			block,
			math.clamp(0.75 * falloff * strength, 0, 0.85),
			1.1 + falloff * 1.4,
			-- Do hloubky zdi, tedy po její lokální ose Z
			Vector3.zAxis
		)
	end
end

function TrackView:build(worldIndex: number)
	self:clear()

	self.WorldIndex = worldIndex
	self.World = Config.Worlds[worldIndex] or Config.Worlds[1]

	local folder = Instance.new("Folder")
	folder.Name = "LocalTrack"
	folder.Parent = Workspace
	self.Folder = folder

	for index = 1, Track.PickupCount do
		local position = Track.pickupPosition(worldIndex, index)
		if position then
			-- Zlatý pickup se pozná ze stejného vzorce jako na serveru,
			-- takže se po síti nic posílat nemusí.
			local golden = Track.isGolden(worldIndex, self.Lap or 0, index)

			local zone = Zones.at(Track.pickupSegment(index))
			local size, tilt, _color, pressAxis = pickupLook(zone)

			self.Pickups[index] = {
				Index = index,
				Part = makePickup(zone, position, golden, folder),
				Position = position,
				Golden = golden,
				ReadyAt = 0,
				BaseSize = if golden then Vector3.new(3.6, 3.6, 3.6) else size,
				Tilt = if golden then CFrame.identity else tilt,
				PressAxis = if golden then -Vector3.yAxis else pressAxis,
				Spin = if golden then true else zone.Pickup.Spin,
			}
		end
	end

	-- Pruhy tekoucí po podlaze ukazují, kam běžet
	Textures.flowStripes(
		folder,
		Track.origin(worldIndex) + Vector3.new(0, 0, -20),
		Track.length(),
		self.World,
		14,
		26
	)

	for index = 1, TRACK.BarrierCount do
		local part, label = makeBarrier(self.World, worldIndex, index, folder, function(barrierIndex)
			return self:chargeRatio(barrierIndex)
		end)
		self.Barriers[index] = {
			Index = index,
			Part = part,
			Label = label,
			Required = Config.barrierPower(worldIndex, index, self.Lap or 0),
			Cracks = 0,
			CrackParts = {},
		}
	end

	--[[
		Vznášející se rekvizity postavil server; klient si je posbírá tady,
		při přestavbě světa. Prohledávat `Workspace` každý snímek by bylo
		to nejdražší, co v celém klientu je.
	]]
	local worlds = Workspace:FindFirstChild("Worlds")
	Textures.collectFloaters(worlds and worlds:FindFirstChild(self.World.Id))

	self:syncBarriers()
end

--[[
	Jak blízko je bariéra k proražení (0..1), nebo nil u neaktivních —
	těm barvu řídí syncBarriers a pulz by jim ji přepisoval.
]]
function TrackView:chargeRatio(index: number): number?
	if index ~= self.Barrier then
		return nil
	end
	local barrier = self.Barriers[index]
	if not barrier then
		return nil
	end
	return math.clamp(self.Power / math.max(barrier.Required, 1), 0, 1)
end

--[[
	Praskliny. Přibývají po krocích, jak Power roste — hráč tak vidí,
	jak blízko je k proražení, i když se nedívá na lištu.

	Kreslí se z tenkých tmavých dílů rozbíhajících se od středu. Textura
	by byla hezčí, ale generovat ji za běhu jde jen s ověřeným účtem,
	takže by se na většině hráčů nezobrazila vůbec.
]]
local CRACK_STEPS = { 0.3, 0.5, 0.7, 0.85, 0.95 }

local function addCrack(barrier: Barrier, world, seed: number)
	local part = barrier.Part
	local random = Random.new(seed)

	local length = random:NextNumber(part.Size.Y * 0.3, part.Size.Y * 0.7)
	local angle = random:NextNumber(0, math.pi * 2)
	local offsetX = random:NextNumber(-part.Size.X * 0.3, part.Size.X * 0.3)
	local offsetY = random:NextNumber(-part.Size.Y * 0.25, part.Size.Y * 0.25)

	local crack = Build.part({
		Name = "Crack",
		Size = Vector3.new(random:NextNumber(0.25, 0.5), length, part.Size.Z + 0.2),
		CFrame = part.CFrame * CFrame.new(offsetX, offsetY, 0) * CFrame.Angles(0, 0, angle),
		Color = Config.Theme.Ink,
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.15,
		CanCollide = false,
		CastShadow = false,
		Parent = part,
	})

	table.insert(barrier.CrackParts, crack)
end

local function clearCracks(barrier: Barrier)
	for _, crack in barrier.CrackParts do
		crack:Destroy()
	end
	table.clear(barrier.CrackParts)
	barrier.Cracks = 0
end

local function updateCracks(barrier: Barrier, world, ratio: number)
	local wanted = 0
	for _, threshold in CRACK_STEPS do
		if ratio >= threshold then
			wanted += 1
		end
	end

	if wanted == barrier.Cracks then
		return
	end

	if wanted < barrier.Cracks then
		clearCracks(barrier)
	end

	while barrier.Cracks < wanted do
		barrier.Cracks += 1
		addCrack(barrier, world, barrier.Index * 977 + barrier.Cracks * 31)
	end
end

-- Průhlednost dílu Beamy nevypne, musí se zhasnout zvlášť
local function setFieldEnabled(part: BasePart, enabled: boolean)
	for _, child in part:GetChildren() do
		if child:IsA("Beam") then
			child.Enabled = enabled
		end
	end
end

function TrackView:clear()
	self:clearSoftSkin()
	self:clearTiles()

	if self.Folder then
		self.Folder:Destroy()
		self.Folder = nil
	end
	Textures.reset()
	self.Pickups = {}
	self.Barriers = {}
end

-- Stav ---------------------------------------------------------------------------

--[[
	Bariéry před hráčem musí zmizet (už jsou proražené), ta aktuální drží
	a ukazuje, kolik Poweru chybí. Další v pořadí jsou zamčené a šedivé.
]]
function TrackView:syncBarriers()
	for index, barrier in self.Barriers do
		if index < self.Barrier then
			--[[
				Tohle je zároveň záchranná síť: efekt průrazu jezdí po
				nespolehlivém kanálu a může se ztratit. Profil ale dorazí
				vždycky, takže se stav bariéry srovná i bez efektu —
				včetně prasklin, které by jinak zůstaly viset ve vzduchu.
			]]
			barrier.Part.CanCollide = false
			barrier.Part.Transparency = 1
			barrier.Label.Text = ""
			setFieldEnabled(barrier.Part, false)
			clearCracks(barrier)
			continue
		end

		if index == self.Barrier then
			if self.SoftSkinFor ~= index then
				self:buildSoftSkin(barrier)
			end

			--[[
				V dohledu je vždycky JEN JEDNA zeď — ta tvoje.

				Dvanáct tabulí za sebou vypadalo jako plot a hráč viděl
				celou trať dopředu, takže nebylo co objevovat. Takhle
				stojí v chodbě jedna obří překážka a za ní se neví nic.
			]]
			local enough = self.Power >= barrier.Required
			barrier.Part.CanCollide = true
			setFieldEnabled(barrier.Part, true)
			barrier.Part.Transparency = 0.15
			barrier.Part.Color = if enough then Config.Theme.Success else self.World.Color
			barrier.Label.Text = if enough
				then `<b>SMASH IT!</b>`
				else `<b>{Format.short(self.Power)} / {Format.short(barrier.Required)}</b>`
			barrier.Label.TextColor3 = if enough then Config.Theme.Success else Config.Theme.Text
		else
			--[[
				Další zdi jsou postavené, ale neviditelné a neprůchozí.
				Neviditelné proto, aby výhled patřil té aktuální; kolizi
				si drží, aby se hráč nedostal dál, než kam má — server
				by mu to stejně neuznal a jen by ho to zmátlo.
			]]
			barrier.Part.CanCollide = true
			setFieldEnabled(barrier.Part, false)
			barrier.Part.Transparency = 1
			barrier.Label.Text = ""
		end
	end
end

function TrackView:setProfile(profile)
	--[[
		Kolo se mění ve stejném okamžiku, kdy se svět NEmění — dojetím
		posledního zdi se hráč vrátí na start téhož světa s vyššími
		požadavky. Bez téhle podmínky by na tabulích zůstala stará čísla
		a hráč by se marně snažil prorazit něco, co server nepustí.
	]]
	local lap = Economy.lap(profile)
	local rebuild = profile.WorldIndex ~= self.WorldIndex or lap ~= self.Lap

	self.Power = profile.Power
	self.Barrier = profile.Barrier
	self.Lap = lap

	--[[
		Zvuk se přebarví podle zóny, ve které hráč zrovna je. Terén se
		mění pod nohama, takže se s ním musí měnit i to, jak zní kroky
		a sbírání — jinak by změna vypadala jako přemalování, ne jako
		jiné místo.
	]]
	local zone = Zones.at(math.clamp(profile.Barrier, 1, TRACK.BarrierCount))
	if zone.Id ~= self.ZoneId then
		self.ZoneId = zone.Id
		SoundKit.setZone(zone.Sound, 1)
	end
	self.PickupValue = profile.PickupValue or 1
	self.CollectRadius = profile.CollectRadius or TRACK.CollectRadius

	if rebuild then
		self:build(profile.WorldIndex)
	else
		self:syncBarriers()
	end
end

--[[
	Aktuální řetěz comba. Trať ho nepoužívá k počítání — jen k tomu, kolik
	jisker u pickupu vypustit. Hodnota chodí ze serveru přes klienta.
]]
function TrackView:setChain(chain: number)
	self.Chain = chain
end

function TrackView:setPower(power: number)
	self.Power = power
	local barrier = self.Barriers[self.Barrier]
	if not barrier then
		CharacterFX.setCharge(0)
		return
	end

	local ratio = power / math.max(barrier.Required, 1)
	CharacterFX.setCharge(ratio)
	updateCracks(barrier, self.World, ratio)

	local enough = power >= barrier.Required
	if enough and not self.WasReady then
		SoundKit.playNamed("Ready", { Position = barrier.Part.Position })
	end
	self.WasReady = enough
	barrier.Part.Color = if enough then Config.Theme.Success else self.World.Color
	barrier.Label.Text = if enough
		then `<b>SMASH IT!</b>`
		else `<b>{Format.short(power)} / {Format.short(barrier.Required)}</b>`
	barrier.Label.TextColor3 = if enough then Config.Theme.Success else Config.Theme.Text
end

-- Proražení bariéry (potvrzené serverem)
function TrackView:breakBarrier(index: number, payload)
	local barrier = self.Barriers[index]
	if not barrier then
		return
	end

	-- Místo nárazu a rychlost hráče rozhodnou, kam a jak daleko kusy odletí
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?

	Effects.smash({
		CFrame = barrier.Part.CFrame,
		Size = barrier.Part.Size,
		World = self.World,
		Payload = payload,
		IsLocal = true,
		Impact = if root then root.Position + Vector3.new(0, 1, 0) else barrier.Part.Position,
		Momentum = if root then root.AssemblyLinearVelocity else Vector3.zero,
		Zone = Zones.at(index).Sound,
	})
	CharacterFX.smash()
	CharacterFX.groundBurst(self.World.Accent)

	-- Měkký povrch patří jedné konkrétní zdi; s jejím pádem musí zmizet
	self:clearSoftSkin()

	barrier.Part.CanCollide = false
	barrier.Part.Transparency = 1
	barrier.Label.Text = ""
	setFieldEnabled(barrier.Part, false)
	clearCracks(barrier)
end

-- Sbírání ------------------------------------------------------------------------

local function hidePickup(pickup: Pickup)
	pickup.Part.Transparency = 1
	pickup.Part.Size = Vector3.new(0.4, 0.4, 0.4)
	pickup.Flying = nil
	pickup.FlyFrom = nil
	local billboard = pickup.Part:FindFirstChild("Info") :: BillboardGui?
	if billboard then
		billboard.Enabled = false
	end
end

--[[
	Start letu k hráči.

	Pickup, který na dotek prostě zmizí, se nedá "cítit". Když místo toho
	vystřelí k hráči a teprve u něj praskne, mozek to přečte jako sebrání.
	Je to nejlevnější úprava s největším dopadem na pocit ze hry.
]]
local function launchPickup(pickup: Pickup, now: number)
	pickup.Flying = now
	pickup.FlyFrom = pickup.Position

	local billboard = pickup.Part:FindFirstChild("Info") :: BillboardGui?
	if billboard then
		billboard.Enabled = false
	end
end

local FLIGHT_SECONDS = 0.22

--[[
	Návrat pickupu po sebrání.

	Dřív vyskočil zpátky pružinou. Teď se objeví **zmáčknutý** a pomalu
	se nafoukne — je to ta samá věc, kterou dělá squishy hračka po
	stisknutí, a sedne to i časově: doba návratu je respawn pickupu.

	Zmáčknutí musí přijít až po nastavení plné velikosti, jinak by se
	`Squish` vrátil k té zmenšené z letu k hráči.
]]
local function showPickup(pickup: Pickup, golden: boolean)
	local part = pickup.Part
	part.Transparency = if golden then 0 else 0
	part.Size = pickup.BaseSize
	part.CFrame = CFrame.new(pickup.Position) * pickup.Tilt

	Squish.rebase(part)
	Squish.press(part, 0.8, TRACK.PickupRespawn * 0.85, pickup.PressAxis)

	local billboard = part:FindFirstChild("Info") :: BillboardGui?
	if billboard then
		billboard.Enabled = true
	end
end

function TrackView:flush()
	if #self.PendingCollects == 0 then
		return
	end

	Remotes.Collect:FireServer(self.PendingCollects)
	self.PendingCollects = {}
end

-- Seznamy indexů po segmentech se spočítají jednou; v Heartbeatu už se
-- jen čtou, aby se každý snímek nealokovaly nové tabulky.
local SEGMENT_INDICES: { { number } } = {}
for segment = 1, TRACK.BarrierCount do
	SEGMENT_INDICES[segment] = Track.segmentPickups(segment)
end

--[[
	Jediná smyčka hry: respawn, animace i sbírání proběhnou v jednom
	průchodu okolím hráče. Celý svět má přes sto pickupů, ale dál než
	o segment dopředu se hráč stejně nedostane — bariéra ho nepustí.
]]
function TrackView:update(now: number, elapsed: number, root: BasePart)
	local origin = Track.origin(self.WorldIndex)
	local segment = math.clamp(
		math.floor((root.Position.Z - origin.Z) / TRACK.SegmentLength) + 1,
		1,
		TRACK.BarrierCount
	)

	local radius = self.CollectRadius
	local position = root.Position
	local collected = 0

	--[[
		Dlaždice se přestavují, až se hráč posune o celý úsek. Sahá se
		na ně o jeden úsek zpátky, aby za ním zůstala stopa důlků —
		kdyby se stavěly až od jeho úseku, mizely by mu za zády.
	]]
	local tileFrom = math.max(segment - 1, 0)
	if self.TileFrom ~= tileFrom then
		self:buildTiles(tileFrom)
	end
	self:pressTiles(position)

	--[[
		Rozhrnutí střepů. Volá se řidčeji než každý snímek — dotaz na
		díly v okolí je nejdražší věc v téhle smyčce a střepy se za dvě
		setiny sekundy nikam neposunou.
	]]
	if now - (self.WadeAt or 0) >= 0.06 then
		self.WadeAt = now
		Fracture.wade(position, root.AssemblyLinearVelocity, 9)
	end

	for offset = -1, 1 do
		local target = segment + offset
		local indices = SEGMENT_INDICES[target]
		if not indices then
			continue
		end

		-- Za aktuální bariéru se hráč nedostane, tamní pickupy neřešíme
		local reachable = target <= self.Barrier

		for _, index in indices do
			local pickup = self.Pickups[index]
			if not pickup then
				continue
			end

			if pickup.ReadyAt > 0 then
				if now < pickup.ReadyAt then
					continue
				end
				pickup.ReadyAt = 0
				pickup.RoseAt = now
				showPickup(pickup, pickup.Golden == true)
			end

			-- Let se řeší dřív než houpání: letícímu pickupu by se pozice
			-- stejně hned přepsala a je to nejteplejší smyčka ve hře.
			if pickup.Flying then
				local progress = (now - pickup.Flying) / FLIGHT_SECONDS

				if progress >= 1 then
					pickup.ReadyAt = now + TRACK.PickupRespawn
					local entry = self.Pickups[index]
					local golden = entry ~= nil and entry.Golden == true
					Effects.pickup(
						position + Vector3.new(0, 2, 0),
						self.PickupValue * (if golden then Config.Track.GoldenValue else 1),
						golden,
						self.Chain
					)
					hidePickup(pickup)
				else
					-- Zrychluje, ne konstantní rychlost: začátek pomalu,
					-- konec prudce, což vypadá jako přitažení magnetem
					local eased = progress * progress
					local target = position + Vector3.new(0, 1.5, 0)
					local from = pickup.FlyFrom :: Vector3

					pickup.Part.CFrame = CFrame.new(from:Lerp(target, eased))
						* CFrame.Angles(0, elapsed * 14, 0)
						* pickup.Tilt
					pickup.Part.Size = pickup.BaseSize * (1 - eased * 0.7)
				end
				continue
			end

			local bob = math.sin(elapsed * 2.2 + index) * 0.5
			--[[
				Houpání se během návratu vypne. Squish si drží původní
				pozici a každý snímek ji přepisuje — kdyby ji houpání
				měnilo pod ním, důlek by po sobě zanechal posunutý díl.
			]]
			if pickup.ReadyAt == 0 and now - (pickup.RoseAt or 0) > TRACK.PickupRespawn then
				local spin = if pickup.Spin then elapsed * 1.6 + index else 0

				pickup.Part.CFrame = CFrame.new(pickup.Position + Vector3.new(0, bob, 0))
					* CFrame.Angles(0, spin, math.rad(20))
					* pickup.Tilt
			end

			if reachable and (pickup.Position - position).Magnitude <= radius then
				launchPickup(pickup, now)
				table.insert(self.PendingCollects, index)
				collected += 1
			end
		end
	end

	-- Dávkování: server dostane jednu zprávu za desetinu sekundy, ne jednu
	-- za každý sebraný kus.
	if collected > 0 and now - self.LastSendAt >= 0.1 then
		self.LastSendAt = now
		self:flush()
	end

	self:checkBarrier(now, root)
end

function TrackView:checkBarrier(now: number, root: BasePart)
	local barrier = self.Barriers[self.Barrier]
	if not barrier then
		return
	end

	local distance = (barrier.Part.Position - root.Position).Magnitude
	if distance > TRACK.SmashRadius + 6 then
		return
	end

	if self.Power >= barrier.Required then
		if now - self.LastSmashAt < 0.4 then
			return
		end
		self.LastSmashAt = now
		-- Odeslat nasbírané dřív, ať server počítá s aktuálním Powerem
		self:flush()
		Remotes.Smash:FireServer(barrier.Index)
	else
		--[[
			Náraz do zdi ji promáčkne, i když hráč nemá dost Poweru.
			Důlek je tady důležitější než hláška: hráč tím dostane odezvu
			na každý dotek, ne jen jednou za půldruhé vteřiny.
		]]
		self:dentWall(root.Position, 1)
		SoundKit.playTerrain("Step", { Position = root.Position, Volume = 0.5 })

		if now - self.LastBlockedAt >= 1.6 then
			self.LastBlockedAt = now
			Effects.blocked(barrier.Part.Position, barrier.Required - self.Power, self.World)
		end
	end
end

function TrackView:start()
	local elapsed = 0

	RunService.Heartbeat:Connect(function(deltaTime)
		elapsed += deltaTime

		if self.WorldIndex == 0 then
			return
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return
		end

		self:update(os.clock(), elapsed, root)
	end)
end

return TrackView

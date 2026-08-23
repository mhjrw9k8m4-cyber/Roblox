--!strict
--[[
	Textures — pohyb povrchů.

	Statická textura vypadá levně; pohybující se vypadá draze. Tenhle modul
	dělá čtyři věci, které v žánru vidíš pořád:

	  1. `scroll`  — posouvá texturu po povrchu (OffsetStudsU/V). Tohle je
	     ta klasická technika na tekoucí energii, běžící pás nebo lávu.
	  2. `energyField` — mřížka Beamů přes bariéru, která proudí nahoru.
	     Beam nepotřebuje žádný obrázek, takže tohle funguje i bez assetů.
	  3. `flowStripes` — pruhy na podlaze, které tečou k bariéře a ukazují,
	     kam běžet.
	  4. `charge` — bariéra pulzuje tím rychleji, čím blíž je proražení.
	     Hráč tak vidí svůj postup i bez koukání na UI.

	Všechno běží z jedné Heartbeat smyčky nad seznamem registrovaných
	efektů — desítky vlastních connectionů by se při přestavbě světa
	musely složitě uklízet.
]]

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Assets = require(Shared.Assets)
local Build = require(Shared.Build)
local Config = require(Shared.Config)

local Textures = {}

type Scroller = {
	Texture: Texture,
	SpeedU: number,
	SpeedV: number,
}

type Pulser = {
	Part: BasePart,
	Base: Color3,
	Peak: Color3,
	-- nil = tuhle bariéru teď neanimuj (barvu si řídí někdo jiný)
	Charge: () -> number?,
}

type Flow = {
	Parts: { BasePart },
	Origin: Vector3,
	Length: number,
	Speed: number,
}

local scrollers: { Scroller } = {}
local pulsers: { Pulser } = {}
local flows: { Flow } = {}
local elapsed = 0

-- Posouvající se textura ---------------------------------------------------------

--[[
	Přidá texturu na jednu stranu dílu a rozpohybuje ji.
	Když v Assets žádné ID není, nevytvoří se nic — díl zůstane
	na svém materiálu a hra vypadá pořád dobře.
]]
function Textures.scroll(part: BasePart, face: Enum.NormalId, options: {
	Asset: string,
	Color: Color3,
	StudsPerTile: number,
	SpeedU: number?,
	SpeedV: number?,
	Transparency: number?,
}): Texture?
	if options.Asset == "" then
		return nil
	end

	local texture = Instance.new("Texture")
	texture.Texture = options.Asset
	texture.Face = face
	texture.Color3 = options.Color
	texture.Transparency = options.Transparency or 0.4
	texture.StudsPerTileU = options.StudsPerTile
	texture.StudsPerTileV = options.StudsPerTile
	texture.Parent = part

	table.insert(scrollers, {
		Texture = texture,
		SpeedU = options.SpeedU or 0,
		SpeedV = options.SpeedV or 0,
	})

	return texture
end

-- Energetické pole na bariéře -------------------------------------------------------

--[[
	Svislé Beamy přes celou bariéru. Beam bez textury je plný barevný pruh,
	takže tohle nepotřebuje jediný nahraný obrázek — a přesto se to hýbe:
	`TextureSpeed` posouvá gradient nahoru pořád dokola.
]]
function Textures.energyField(part: BasePart, world, count: number)
	local width = part.Size.X
	local height = part.Size.Y

	for index = 1, count do
		local offsetX = -width / 2 + width * (index - 0.5) / count

		local bottom = Instance.new("Attachment")
		bottom.Position = Vector3.new(offsetX, -height / 2, 0)
		bottom.Parent = part

		local top = Instance.new("Attachment")
		top.Position = Vector3.new(offsetX, height / 2, 0)
		top.Parent = part

		local beam = Instance.new("Beam")
		beam.Attachment0 = bottom
		beam.Attachment1 = top
		beam.Width0 = width / count * 0.55
		beam.Width1 = width / count * 0.55
		beam.FaceCamera = false
		beam.LightEmission = 0.9
		beam.LightInfluence = 0
		beam.Segments = 4
		beam.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, world.Accent),
			ColorSequenceKeypoint.new(0.5, world.Color),
			ColorSequenceKeypoint.new(1, world.Accent),
		})
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.85),
			NumberSequenceKeypoint.new(0.35, 0.35),
			NumberSequenceKeypoint.new(0.65, 0.35),
			NumberSequenceKeypoint.new(1, 0.85),
		})
		-- Rychlost se liší pruh od pruhu, aby pole nevypadalo jako mřížka
		beam.TextureSpeed = 1.4 + (index % 3) * 0.35
		beam.TextureLength = 6
		beam.Parent = part
	end
end

-- Pruhy na podlaze ------------------------------------------------------------------

--[[
	Světelné pruhy, které tečou po podlaze směrem k další bariéře.
	Kromě parády mají i funkci: ukazují, kam běžet.
]]
function Textures.flowStripes(parent: Instance, origin: Vector3, length: number, world, count: number, speed: number)
	local parts = table.create(count)

	for index = 1, count do
		parts[index] = Build.part({
			Name = "Stripe",
			Size = Vector3.new(Config.Track.Width - 10, 0.2, 5),
			Position = origin + Vector3.new(0, 0.3, length * (index - 1) / count),
			Color = world.Accent,
			Material = Enum.Material.Neon,
			Transparency = 0.6,
			CanCollide = false,
			CastShadow = false,
			Parent = parent,
		})
	end

	table.insert(flows, {
		Parts = parts,
		Origin = origin + Vector3.new(0, 0.3, 0),
		Length = length,
		Speed = speed,
	})
end

-- Pulzování podle nabití --------------------------------------------------------------

--[[
	Bariéra dýchá tím rychleji, čím blíž je proražení.

	`charge` je funkce, ne číslo — nabití se mění každý snímek. Když vrátí
	nil, modul se barvy nedotkne: zamčené a proražené bariéry si barvu
	řídí samy a pulz by jim ji přepisoval.
]]
function Textures.charge(part: BasePart, base: Color3, peak: Color3, charge: () -> number?)
	table.insert(pulsers, {
		Part = part,
		Base = base,
		Peak = peak,
		Charge = charge,
	})
end

-- Úklid a smyčka -------------------------------------------------------------------

-- Při přestavbě světa se díly zničí; osiřelé záznamy odsud vypadnou samy.
local function prune()
	for index = #scrollers, 1, -1 do
		if not scrollers[index].Texture.Parent then
			table.remove(scrollers, index)
		end
	end
	for index = #pulsers, 1, -1 do
		if not pulsers[index].Part.Parent then
			table.remove(pulsers, index)
		end
	end
	for index = #flows, 1, -1 do
		if not flows[index].Parts[1].Parent then
			table.remove(flows, index)
		end
	end
end

function Textures.reset()
	table.clear(scrollers)
	table.clear(pulsers)
	table.clear(flows)
end

function Textures.start()
	local sincePrune = 0

	RunService.Heartbeat:Connect(function(deltaTime)
		elapsed += deltaTime
		sincePrune += deltaTime

		for _, scroller in scrollers do
			local texture = scroller.Texture
			if scroller.SpeedU ~= 0 then
				texture.OffsetStudsU = (texture.OffsetStudsU + scroller.SpeedU * deltaTime) % texture.StudsPerTileU
			end
			if scroller.SpeedV ~= 0 then
				texture.OffsetStudsV = (texture.OffsetStudsV + scroller.SpeedV * deltaTime) % texture.StudsPerTileV
			end
		end

		for _, pulser in pulsers do
			local charge = pulser.Charge()
			if charge then
				local wave = (math.sin(elapsed * (3 + charge * 14)) + 1) / 2
				pulser.Part.Color = pulser.Base:Lerp(pulser.Peak, wave * 0.75)
			end
		end

		-- Pruhy tečou dopředu a na konci trati se vrátí na začátek.
		-- Modulo drží pozici v rozsahu tratě bez dopočítávání stavu.
		for _, flow in flows do
			local count = #flow.Parts
			local spacing = flow.Length / count
			local shift = (elapsed * flow.Speed) % spacing

			for index, part in flow.Parts do
				local base = spacing * (index - 1) + shift
				part.Position = flow.Origin + Vector3.new(0, 0, base % flow.Length)
			end
		end

		if sincePrune >= 2 then
			sincePrune = 0
			prune()
		end
	end)
end

-- Textura z Assets podle role ("Barrier" / "Floor" / "Wall")
function Textures.assetFor(role: string): string
	return Assets.Textures[role] or ""
end

return Textures

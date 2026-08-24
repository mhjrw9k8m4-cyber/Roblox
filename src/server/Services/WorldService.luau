--!strict
--[[
	WorldService — postaví tratě všech světů z kódu.

	Staví se jen to, co je pro všechny stejné: podlaha, stěny, rámy dveří,
	startovní a cílová plošina. Samotné prorazitelné tabule a pickupy staví
	klient lokálně — musí totiž blokovat a mizet každému hráči zvlášť podle
	jeho vlastního postupu, což sdílená geometrie neumí.
]]

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Build = require(Shared.Build)
local Config = require(Shared.Config)
local Props = require(Shared.Props)
local Track = require(Shared.Track)
local Zones = require(Shared.Zones)

local WorldService = {}

local TRACK = Config.Track

--[[
	Osvětlení ve stylu, ve kterém jsou dělané populární Roblox hry:
	**jasné, syté a bez oparu**.

	Předchozí verze byla temná a zamlžená — vypadalo to "filmově", ale
	právě to je v tomhle žánru špatně. Hráč má vidět celou chodbu naráz,
	barvy mají svítit a nic se nemá ztrácet ve stínu. Šero a mlha jsou
	nástroje hororu, ne barevného simulátoru.

	Konkrétně: vyšší jas, světlejší ambient (žádné černé stíny), mlha až
	daleko a jen slabý opar.
]]
local function buildLighting()
	Lighting.Ambient = Color3.fromRGB(126, 118, 148)
	Lighting.OutdoorAmbient = Color3.fromRGB(146, 138, 168)
	Lighting.Brightness = 3
	Lighting.ClockTime = 14
	Lighting.EnvironmentDiffuseScale = 0.7
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.GlobalShadows = true

	for _, className in { "Atmosphere", "BloomEffect", "ColorCorrectionEffect" } do
		local existing = Lighting:FindFirstChildOfClass(className)
		if existing then
			existing:Destroy()
		end
	end

	local atmosphere = Instance.new("Atmosphere")
	-- Skoro nic: opar má barvám dát hloubku, ne je zašedit
	atmosphere.Density = 0.08
	atmosphere.Haze = 0.4
	atmosphere.Glare = 0.1
	atmosphere.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	-- Bloom zůstává silný: rozzářené neony jsou v žánru podpis
	bloom.Intensity = 1.3
	bloom.Size = 24
	bloom.Threshold = 0.9
	bloom.Parent = Lighting

	local color = Instance.new("ColorCorrectionEffect")
	-- Víc barvy, míň kontrastu: sytě a čitelně, ne "filmově"
	color.Saturation = 0.35
	color.Contrast = 0.05
	color.Brightness = 0.02
	color.Parent = Lighting

	--[[
		Obloha bez jediné textury.

		`Sky` s prázdnými `SkyboxUp/Dn/...` vykreslí jednolitou plochu —
		tu ale nechceme vidět, protože mlha končí dřív. Co z oblohy
		zbývá vidět, jsou hvězdy a slunce, a ty stačí naladit: hustá
		hvězdná obloha za mlhou vypadá jako hloubka, ne jako stěna.

		Barvu oblohy pak přebarví mlha podle světa (viz klient), takže
		tady se řeší jen struktura.
	]]
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky then
		sky:Destroy()
	end

	sky = Instance.new("Sky")
	sky.StarCount = 3000
	sky.SunAngularSize = 12
	sky.MoonAngularSize = 0
	sky.CelestialBodiesShown = true
	sky.Parent = Lighting

	--[[
		Sluneční paprsky. Nejlevnější efekt, který dá scéně objem —
		světlo se opře do oblouků a chodba dostane hloubku.
	]]
	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if rays then
		rays:Destroy()
	end

	rays = Instance.new("SunRaysEffect")
	-- Jen naznačit; silné paprsky ve vnitřní chodbě vypadají jako závada
	rays.Intensity = 0.06
	rays.Spread = 0.5
	rays.Parent = Lighting

	--[[
		Hloubka ostrosti se NEPOUŽÍVÁ.

		Byla tam a je pryč. Rozostřená dálka je filmový efekt a v Roblox
		simulátoru působí jako rozmazaná grafika — hráč má vidět ostře
		celou chodbu včetně zdi na konci. Populární hry v žánru ji nemají
		ani jedna.

		Zbylá po předchozí verzi se maže, ne jen vypíná: vypnutý efekt
		by se dal omylem zapnout a nikdo by nevěděl proč.
	]]
	local depth = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if depth then
		depth:Destroy()
	end
end

--[[
	Startovní plošina se jménem světa. Zároveň je to místo, kam se hráč
	teleportuje při vstupu do světa i po resetu postavy.
]]
local function buildStart(world, worldIndex: number, parent: Instance)
	local origin = Track.origin(worldIndex)

	local pad = Build.part({
		Name = "Start",
		Size = Vector3.new(TRACK.Width, 2, 44),
		Position = origin + Vector3.new(0, 1, -24),
		Color = world.Accent,
		Material = Enum.Material.Neon,
		Transparency = 0.25,
		Parent = parent,
	})
	Build.light(pad, world.Accent, 3, 40)

	local sign = Build.part({
		Name = "Cedule",
		Size = Vector3.new(30, 8, 1),
		Position = origin + Vector3.new(0, 16, -44),
		Color = Config.Theme.Panel,
		CanCollide = false,
		Parent = parent,
	})

	Build.billboard({
		Adornee = sign,
		Text = `<b>{world.Name:upper()}</b>`,
		Size = UDim2.fromScale(30, 8),
		Color = world.Color,
		MaxDistance = 500,
	})
end

-- Cílová plošina za poslední bariérou
local function buildFinish(world, worldIndex: number, parent: Instance)
	local position = Track.finishPosition(worldIndex)

	local pad = Build.part({
		Name = "Finish",
		Size = Vector3.new(TRACK.Width, 2, 40),
		Position = position + Vector3.new(0, -3, 0),
		Color = Config.Theme.Success,
		Material = Enum.Material.Neon,
		Transparency = 0.2,
		Parent = parent,
	})
	Build.light(pad, Config.Theme.Success, 4, 50)

	local sign = Build.part({
		Name = "Cedule",
		Size = Vector3.new(34, 9, 1),
		Position = position + Vector3.new(0, 14, 16),
		Color = Config.Theme.Panel,
		CanCollide = false,
		Parent = parent,
	})

	Build.billboard({
		Adornee = sign,
		Text = "<b>WORLD CLEARED!</b>",
		Size = UDim2.fromScale(34, 9),
		Color = Config.Theme.Success,
		MaxDistance = 500,
	})
end

-- Rám kolem bariéry: sloupky a překlad, aby tabule vypadala zasazeně
local function buildBarrierFrame(world, worldIndex: number, index: number, parent: Instance)
	local center = Track.barrierPosition(worldIndex, index)

	for _, side in { -1, 1 } do
		local pillar = Build.part({
			Name = "Sloupek",
			Size = Vector3.new(3, 22, 3),
			Position = center + Vector3.new(side * (TRACK.Width / 2 - 1.5), 5, 0),
			Color = Config.Theme.PanelLight,
			Material = Enum.Material.Metal,
			Parent = parent,
		})

		local lamp = Build.part({
			Name = "Světlo",
			Size = Vector3.new(2, 1.4, 2),
			Position = center + Vector3.new(side * (TRACK.Width / 2 - 1.5), 16, 0),
			Color = world.Accent,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
			Parent = parent,
		})
		Build.light(lamp, world.Accent, 2.5, 30)
		pillar.CastShadow = false
	end

	Build.part({
		Name = "Překlad",
		Size = Vector3.new(TRACK.Width, 3, 3),
		Position = center + Vector3.new(0, 17.5, 0),
		Color = Config.Theme.PanelLight,
		Material = Enum.Material.Metal,
		CastShadow = false,
		Parent = parent,
	})
end

--[[
	Architektura tratě.

	Chodba z podlahy a dvou zdí je technicky správně a vypadá jako krabice.
	Rozdíl mezi „prototyp" a „hra" dělá to, že prostor má **rytmus** —
	něco, co se opakuje a čím kolem tebe ubíhá, takže je vidět rychlost.

	Tři vrstvy, každá v jiné vzdálenosti:
	  * oblouky u každé zdi   — rámují cíl, na který běžíš
	  * sloupy mezi zdmi      — rytmus přímo vedle tebe
	  * plovoucí kry v dálce  — hloubka za stěnami

	Všechno je ukotvené, bez kolizí a bez dotazů, takže to nic nestojí
	kromě vykreslení. Stín vrhají jen sloupy — u průsvitných ker by byl
	stín jen šum.
]]

-- Oblouk nad každou bariérou. Nese barvu světa a zvedá strop, takže
-- chodba nepůsobí jako tunel s víkem.
local function buildArch(world, origin: Vector3, z: number, parent: Instance)
	local half = TRACK.Width / 2 + 2

	for _, side in { -1, 1 } do
		Build.part({
			Name = "Sloup oblouku",
			Size = Vector3.new(2.4, 30, 2.4),
			Position = origin + Vector3.new(side * half, 15, z),
			Color = Config.Theme.Background,
			Material = Enum.Material.Concrete,
			CanCollide = false,
			Parent = parent,
		})

		local glow = Build.part({
			Name = "Svit oblouku",
			Size = Vector3.new(0.8, 26, 0.8),
			Position = origin + Vector3.new(side * (half - 1.4), 15, z),
			Color = world.Accent,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
			Parent = parent,
		})
		glow.Transparency = 0.1
		Build.light(glow, world.Accent, 1.6, 26)
	end

	-- Překlad. Mírně nad zdí, aby přes něj šlo vidět rozpad tabule.
	Build.part({
		Name = "Překlad oblouku",
		Size = Vector3.new(TRACK.Width + 8, 3.2, 3),
		Position = origin + Vector3.new(0, 30, z),
		Color = Config.Theme.Background,
		Material = Enum.Material.Concrete,
		CanCollide = false,
		Parent = parent,
	})

	local bar = Build.part({
		Name = "Světlo překladu",
		Size = Vector3.new(TRACK.Width + 2, 0.7, 1.2),
		Position = origin + Vector3.new(0, 28.2, z),
		Color = world.Color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
		Parent = parent,
	})
	bar.Transparency = 0.05
end

--[[
	Sloupy mezi bariérami. Tohle je ta vrstva, kterou hráč při běhu vnímá
	nejvíc — míjí je nejblíž, takže dělají pocit rychlosti.
]]
local function buildPillars(world, origin: Vector3, z: number, parent: Instance)
	local half = TRACK.Width / 2 - 1.2

	for _, side in { -1, 1 } do
		local pillar = Build.part({
			Name = "Sloup",
			Size = Vector3.new(1.8, 12, 1.8),
			Position = origin + Vector3.new(side * half, 6, z),
			Color = world.Color,
			Material = world.Material,
			CanCollide = false,
			Parent = parent,
		})
		pillar.Transparency = 0.35
		pillar.Reflectance = 0.3

		local cap = Build.part({
			Name = "Hlavice",
			Size = Vector3.new(2.6, 1.4, 2.6),
			Position = origin + Vector3.new(side * half, 12.6, z),
			Color = world.Accent,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
			Shape = Enum.PartType.Ball,
			Parent = parent,
		})
		-- Bez PointLightu schválně: Neon svítí sám a světel je v chodbě
		-- už tak dost. Světla jsou to nejdražší, co se dá do světa dát.
		cap.Transparency = 0.1
	end
end

--[[
	Plovoucí kry za stěnami. Hloubka pozadí za pár dílů — bez nich končí
	svět tři metry od hráče a je to znát.

	Velikosti a natočení se odvozují z indexu, ne z náhody: svět tak
	vypadá na každém serveru stejně a jde ho reprodukovat.
]]
local function buildDrift(world, origin: Vector3, length: number, parent: Instance)
	local count = 26

	for index = 1, count do
		local t = index / count
		local side = if index % 2 == 0 then 1 else -1
		local distance = TRACK.Width / 2 + 18 + (index % 5) * 9
		local height = 6 + (index % 7) * 7
		local size = 5 + (index % 4) * 4

		local shard = Build.part({
			Name = "Kra",
			Size = Vector3.new(size, size * 1.6, size),
			CFrame = CFrame.new(origin + Vector3.new(side * distance, height, length * t))
				* CFrame.Angles(index * 0.4, index * 0.7, index * 0.23),
			Color = world.Color,
			Material = world.Material,
			CanCollide = false,
			CastShadow = false,
			Parent = parent,
		})
		shard.Transparency = 0.55
		shard.Reflectance = 0.35
	end
end

--[[
	Cedule na začátku zóny.

	Bez ní by se terén změnil "jen tak" a hráč by nevěděl, že něčeho
	dosáhl. S ní je přechod odměna: jméno zóny a kolik Poweru stála zeď,
	kterou k ní musel prorazit.

	Visí nad tratí u kraje, ne uprostřed — uprostřed by zakrývala zeď,
	na kterou hráč běží.
]]
local function buildZoneSign(world, worldIndex: number, barrierIndex: number, parent: Instance)
	local zone = Zones.startsAt(barrierIndex)
	if not zone then
		return
	end

	local position = Track.barrierPosition(worldIndex, barrierIndex)
		+ Vector3.new(TRACK.Width / 2 - 3, 12, -TRACK.SegmentLength / 2)

	local post = Build.part({
		Name = `Cedule {zone.Id}`,
		Size = Vector3.new(6, 3.4, 0.6),
		Position = position,
		Color = zone.Floor,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CastShadow = false,
		Parent = parent,
	})
	Build.light(post, zone.Edge, 1.2, 18)

	Build.billboard({
		Adornee = post,
		Text = `<b>{string.upper(zone.Name)}</b>`,
		Size = UDim2.fromScale(14, 3),
		Offset = Vector3.new(0, 3.4, 0),
		Color = zone.Edge,
		MaxDistance = 320,
	})

	Build.billboard({
		Adornee = post,
		Text = `WALL {barrierIndex}+`,
		Size = UDim2.fromScale(10, 2),
		Offset = Vector3.new(0, 1.4, 0),
		Color = Config.Theme.Text,
		MaxDistance = 240,
	})
end

--[[
	Rekvizity světa.

	Popis je v `Shared.Props`, tady se z něj skládají díly. Barvy se
	v datech uvádějí jménem role, ne hexem — dosadí se až tady, takže
	jedna rekvizita může posloužit víc světům a nikde se neopisuje.
]]
local function resolveColor(role: string, world): Color3
	if role == "Accent" then
		return world.Accent
	elseif role == "Dark" then
		return world.Fog:Lerp(Color3.new(0, 0, 0), 0.25)
	elseif role == "Light" then
		return world.Color:Lerp(Color3.new(1, 1, 1), 0.45)
	end
	return world.Color
end

local SHAPES = {
	Block = Enum.PartType.Block,
	Ball = Enum.PartType.Ball,
	Cylinder = Enum.PartType.Cylinder,
	Wedge = Enum.PartType.Wedge,
}

local function buildProp(prop, world, base: CFrame, parent: Instance)
	local model = Instance.new("Model")
	model.Name = prop.Id
	model.Parent = parent

	for _, item in prop.Pieces do
		local rotation = item.Rotation or Vector3.zero
		local part = Build.part({
			Name = prop.Id,
			Size = item.Size,
			CFrame = base
				* CFrame.new(item.Offset)
				* CFrame.Angles(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z)),
			Color = resolveColor(item.Color, world),
			Material = (Enum.Material :: any)[item.Material] or Enum.Material.SmoothPlastic,
			Transparency = item.Transparency or 0,
			Shape = SHAPES[item.Shape],
			-- Rekvizity stojí mimo trať, takže do nich hráč nemůže vrazit.
			-- Bez kolize navíc nestojí nic na fyzice.
			CanCollide = false,
			Parent = model,
		})

		if item.Glow then
			Build.light(part, resolveColor(item.Color, world), item.Glow, 16)
		end

		--[[
			Vznášející se rekvizita se označí atributem. Klient si takové
			díly posbírá a animuje je v jedné smyčce — server na to nesahá,
			protože pohyb, který nikoho neovlivňuje, nepatří na server.
		]]
		if prop.Float then
			part:SetAttribute("Float", prop.Float)
		end
	end
end

--[[
	Rozestavění rekvizit podél trati.

	Jde se po úsecích mezi zdmi a u každého se zkusí každá rekvizita.
	`Every` říká, po kolika úsecích se opakuje — tím vzniká rytmus
	a ne les.
]]
local function buildProps(world, worldIndex: number, parent: Instance)
	local props = Props.forWorld(world.Id)
	if #props == 0 then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "Rekvizity"
	folder.Parent = parent

	local origin = Track.origin(worldIndex)

	for segment = 0, TRACK.BarrierCount do
		local z = segment * TRACK.SegmentLength - TRACK.SegmentLength / 2

		for _, prop in props do
			if segment % prop.Every ~= 0 then
				continue
			end

			for _, side in Props.sides(prop) do
				--[[
					Natočení dovnitř: rekvizita vlevo se otočí doprava
					a naopak. Bez toho by všechny koukaly stejným směrem
					a jedna strana trati by vypadala odvráceně.
				]]
				local yaw = if side == 0 then 0 else -side * math.rad(14)
				local base = CFrame.new(origin + Vector3.new(side * prop.Distance, prop.Height, z))
					* CFrame.Angles(0, yaw, 0)

				buildProp(prop, world, base, folder)
			end
		end
	end
end

local function buildTrack(world, worldIndex: number, parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = world.Id
	folder.Parent = parent

	local origin = Track.origin(worldIndex)
	local length = Track.length() + 90
	local centerZ = length / 2 - 50

	--[[
		Podlaha po úsecích, ne jedním kusem.

		Každý úsek mezi zdmi patří do zóny (viz `Shared.Zones`) a nese její
		barvu a materiál. Hráč tak vidí postup pod nohama, ne jen v číslech
		— a přechod přes zeď je vstup někam jinam, ne další stejný metr.
	]]
	for index = 0, TRACK.BarrierCount do
		local zone = Zones.at(math.max(index, 1))
		local material = (Enum.Material :: any)[zone.Material] or Enum.Material.Concrete

		local slab = Build.part({
			Name = `Podlaha {zone.Id}`,
			Size = Vector3.new(TRACK.Width, 4, TRACK.SegmentLength),
			Position = origin + Vector3.new(0, -2, index * TRACK.SegmentLength - TRACK.SegmentLength / 2),
			Color = zone.Floor,
			Material = material,
			Parent = folder,
		})
		slab.Reflectance = zone.Reflectance
		slab.Transparency = zone.Transparency

		-- Světlý lem po okrajích úseku: hranice zón je tím vidět už z dálky
		for _, side in { -1, 1 } do
			Build.part({
				Name = "Lem",
				Size = Vector3.new(1.6, 0.3, TRACK.SegmentLength),
				Position = origin
					+ Vector3.new(side * (TRACK.Width / 2 - 0.8), 0.15, index * TRACK.SegmentLength - TRACK.SegmentLength / 2),
				Color = zone.Edge,
				Material = Enum.Material.Neon,
				Transparency = 0.35,
				CanCollide = false,
				CastShadow = false,
				Parent = folder,
			})
		end
	end

	--[[
		Příčné pásy v podlaze. Jednolitá plocha rychlost neukáže — oko
		nemá čeho se chytit. Pás každých pár metrů udělá z běhu pohyb.
	]]
	local stripeCount = math.floor(length / 20)
	for index = 0, stripeCount do
		-- Práh nese barvu zóny, ve které leží, ne barvu celého světa
		local zone = Zones.at(math.clamp((index * 20) // TRACK.SegmentLength + 1, 1, TRACK.BarrierCount))

		local band = Build.part({
			Name = "Práh",
			Size = Vector3.new(TRACK.Width - 6, 0.14, 1.6),
			Position = origin + Vector3.new(0, 0.08, index * 20 - 40),
			Color = zone.Edge,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
			Parent = folder,
		})
		-- Každý čtvrtý výraznější, aby vznikl takt, ne jen mřížka
		band.Transparency = if index % 4 == 0 then 0.35 else 0.82
	end

	-- Neonové pásy po stranách, aby byl vidět směr běhu
	for _, side in { -1, 1 } do
		Build.part({
			Name = "Zeď",
			Size = Vector3.new(3, 26, length),
			Position = origin + Vector3.new(side * (TRACK.Width / 2 + 1), 11, centerZ),
			Color = Config.Theme.Background,
			Material = Enum.Material.Concrete,
			Parent = folder,
		})

		local strip = Build.part({
			Name = "Pás",
			Size = Vector3.new(0.6, 1, length),
			Position = origin + Vector3.new(side * (TRACK.Width / 2 - 0.4), 1.4, centerZ),
			Color = world.Accent,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
			Parent = folder,
		})
		strip.Transparency = 0.15
	end

	buildStart(world, worldIndex, folder)
	buildFinish(world, worldIndex, folder)
	buildDrift(world, origin, length, folder)
	buildProps(world, worldIndex, folder)

	for index = 1, TRACK.BarrierCount do
		buildBarrierFrame(world, worldIndex, index, folder)

		local z = Track.barrierPosition(worldIndex, index).Z - origin.Z
		buildArch(world, origin, z, folder)
		buildZoneSign(world, worldIndex, index, folder)
		-- Sloup do půlky mezi tuhle a další bariéru
		buildPillars(world, origin, z + TRACK.SegmentLength / 2, folder)
	end

	return folder
end

function WorldService.build()
	buildLighting()

	local existing = Workspace:FindFirstChild("Worlds")
	if existing then
		existing:Destroy()
	end

	local root = Instance.new("Folder")
	root.Name = "Worlds"
	root.Parent = Workspace

	for index, world in Config.Worlds do
		buildTrack(world, index, root)
	end

	-- Hráči se do světů teleportují ručně; výchozí spawn ať je u prvního
	local spawnLocation = Workspace:FindFirstChildOfClass("SpawnLocation")
	if spawnLocation then
		spawnLocation:Destroy()
	end

	local spawnPad = Instance.new("SpawnLocation")
	spawnPad.Name = "Spawn"
	spawnPad.Size = Vector3.new(10, 1, 10)
	spawnPad.CFrame = Track.spawnCFrame(1)
	spawnPad.Anchored = true
	spawnPad.Transparency = 1
	spawnPad.CanCollide = false
	spawnPad.Duration = 0
	spawnPad.Neutral = true
	spawnPad.Parent = root

	return root
end

return WorldService

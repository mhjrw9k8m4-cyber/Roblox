--!strict
--[[
	WorldService — postaví celý hub z kódu.

	Ve Studiu tedy nemusí být předem nic: podlaha, stanice, osvětlení
	i atmosféra vzniknou při startu serveru. Změna vzhledu = změna kódu.
]]

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Build = require(Shared.Build)
local Config = require(Shared.Config)

local WorldService = {}

local FLOOR_RADIUS = Config.Core.StationRadius + 34

function WorldService.stationCFrame(index: number): CFrame
	local angle = (index - 1) / Config.Core.StationCount * math.pi * 2
	local position = Vector3.new(
		math.cos(angle) * Config.Core.StationRadius,
		0,
		math.sin(angle) * Config.Core.StationRadius
	)
	-- stanice je otočená čelem do středu hubu
	return CFrame.lookAt(position, Vector3.new(0, position.Y, 0))
end

local function buildLighting()
	Lighting.Ambient = Color3.fromRGB(46, 40, 66)
	Lighting.OutdoorAmbient = Color3.fromRGB(58, 50, 82)
	Lighting.Brightness = 1.6
	Lighting.ClockTime = 21
	Lighting.GeographicLatitude = 12
	Lighting.EnvironmentDiffuseScale = 0.45
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.GlobalShadows = true
	Lighting.FogColor = Color3.fromRGB(24, 20, 40)
	Lighting.FogStart = 60
	Lighting.FogEnd = 340

	for _, className in { "Atmosphere", "Bloom", "ColorCorrectionEffect", "SunRaysEffect" } do
		local existing = Lighting:FindFirstChildOfClass(className)
		if existing then
			existing:Destroy()
		end
	end

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.32
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(190, 175, 220)
	atmosphere.Decay = Color3.fromRGB(90, 76, 130)
	atmosphere.Glare = 0.3
	atmosphere.Haze = 1.4
	atmosphere.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.9
	bloom.Size = 32
	bloom.Threshold = 0.9
	bloom.Parent = Lighting

	local colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Saturation = 0.18
	colorCorrection.Contrast = 0.12
	colorCorrection.TintColor = Color3.fromRGB(255, 246, 255)
	colorCorrection.Parent = Lighting
end

local function buildFloor(parent: Instance)
	local floor = Build.part({
		Name = "Podlaha",
		Size = Vector3.new(FLOOR_RADIUS * 2, 4, FLOOR_RADIUS * 2),
		Position = Vector3.new(0, -2, 0),
		Color = Config.Theme.Background,
		Material = Enum.Material.Marble,
		Reflectance = 0.06,
		Parent = parent,
	})

	-- Kruhový "koberec" uprostřed pro orientaci
	Build.part({
		Name = "Střed",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 26, 26),
		CFrame = CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Config.Theme.PanelLight,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = parent,
	})

	-- Neonový prstenec kolem středu
	local segments = 48
	for index = 1, segments do
		local angle = index / segments * math.pi * 2
		local radius = 14
		local part = Build.part({
			Name = "Prstenec",
			Size = Vector3.new(1.6, 0.3, 0.6),
			CFrame = CFrame.new(math.cos(angle) * radius, 0.4, math.sin(angle) * radius)
				* CFrame.Angles(0, -angle, 0),
			Color = if index % 2 == 0 then Config.Theme.Accent else Config.Theme.Accent2,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = parent,
		})
		part.CastShadow = false
	end

	-- Stěny, aby hráč nespadl z mapy
	for index = 1, 4 do
		local angle = (index - 1) * math.pi / 2
		Build.part({
			Name = "Stěna",
			Size = Vector3.new(FLOOR_RADIUS * 2, 40, 4),
			CFrame = CFrame.new(math.sin(angle) * FLOOR_RADIUS, 18, math.cos(angle) * FLOOR_RADIUS)
				* CFrame.Angles(0, angle, 0),
			Color = Config.Theme.Panel,
			Material = Enum.Material.Concrete,
			Transparency = 0.35,
			Parent = parent,
		})
	end

	return floor
end

local function buildSpawn(parent: Instance)
	local existing = Workspace:FindFirstChildOfClass("SpawnLocation")
	if existing then
		existing:Destroy()
	end

	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "Spawn"
	spawnLocation.Size = Vector3.new(12, 1, 12)
	spawnLocation.CFrame = CFrame.new(0, 0.5, 0)
	spawnLocation.Anchored = true
	spawnLocation.CanCollide = true
	spawnLocation.Color = Config.Theme.Accent
	spawnLocation.Material = Enum.Material.Neon
	spawnLocation.Transparency = 0.25
	spawnLocation.TopSurface = Enum.SurfaceType.Smooth
	spawnLocation.BottomSurface = Enum.SurfaceType.Smooth
	spawnLocation.Duration = 0
	spawnLocation.Parent = parent

	Build.pointLight(spawnLocation, Config.Theme.Accent, 3, 30)
	return spawnLocation
end

--[[
	Jedna stanice: pult, na kterém se objevuje materiál, cedule se jménem
	hráče a nasvícení. Vrací složku se všemi díly.
]]
local function buildStation(index: number, parent: Instance): Folder
	local baseCFrame = WorldService.stationCFrame(index)

	local station = Instance.new("Folder")
	station.Name = `Stanice{index}`
	station.Parent = parent

	local desk = Build.part({
		Name = "Pult",
		Size = Vector3.new(14, 4, 10),
		CFrame = baseCFrame * CFrame.new(0, 2, 0),
		Color = Config.Theme.Panel,
		Material = Enum.Material.WoodPlanks,
		Parent = station,
	})

	Build.part({
		Name = "Deska",
		Size = Vector3.new(14.6, 0.6, 10.6),
		CFrame = baseCFrame * CFrame.new(0, 4.3, 0),
		Color = Config.Theme.PanelLight,
		Material = Enum.Material.Marble,
		Reflectance = 0.1,
		Parent = station,
	})

	-- Podložka, nad kterou se vznáší materiál
	local pad = Build.part({
		Name = "Podložka",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, 8, 8),
		CFrame = baseCFrame * CFrame.new(0, 4.8, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Config.Theme.Accent2,
		Material = Enum.Material.Neon,
		Transparency = 0.4,
		CanCollide = false,
		Parent = station,
	})
	pad.CastShadow = false
	Build.pointLight(pad, Config.Theme.Accent2, 2.4, 22)

	-- Bod, kde se objekt vznáší (kotva pro ASMRService)
	local anchor = Build.part({
		Name = "Kotva",
		Size = Vector3.new(1, 1, 1),
		CFrame = baseCFrame * CFrame.new(0, 8.5, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		Parent = station,
	})

	-- Cedule nad stanicí
	local sign = Build.part({
		Name = "Cedule",
		Size = Vector3.new(13, 3.4, 0.5),
		CFrame = baseCFrame * CFrame.new(0, 14, -4),
		Color = Config.Theme.Panel,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = station,
	})

	local label = Build.billboard(sign, "<b>VOLNÁ STANICE</b>", UDim2.fromScale(13, 3.4), Vector3.zero)
	label.TextColor3 = Config.Theme.TextDim
	label.Name = "Jmenovka"

	-- Sloupky se světlem po stranách
	for _, side in { -1, 1 } do
		local pillar = Build.part({
			Name = "Sloupek",
			Size = Vector3.new(1.2, 12, 1.2),
			CFrame = baseCFrame * CFrame.new(side * 7.4, 6, -3.6),
			Color = Config.Theme.PanelLight,
			Material = Enum.Material.Metal,
			Parent = station,
		})

		local lamp = Build.part({
			Name = "Světlo",
			Size = Vector3.new(1.6, 0.8, 1.6),
			CFrame = baseCFrame * CFrame.new(side * 7.4, 12.2, -3.6),
			Color = Config.Theme.Accent,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = station,
		})
		lamp.CastShadow = false
		Build.pointLight(lamp, Config.Theme.Accent, 2, 26)
		pillar.CastShadow = false
	end

	station:SetAttribute("Index", index)
	return station
end

function WorldService.build(): Folder
	buildLighting()

	local existing = Workspace:FindFirstChild("Svět")
	if existing then
		existing:Destroy()
	end

	local world = Instance.new("Folder")
	world.Name = "Svět"
	world.Parent = Workspace

	buildFloor(world)
	buildSpawn(world)

	local stations = Instance.new("Folder")
	stations.Name = "Stanice"
	stations.Parent = world

	for index = 1, Config.Core.StationCount do
		buildStation(index, stations)
	end

	return world
end

return WorldService

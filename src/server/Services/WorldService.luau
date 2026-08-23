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
local Track = require(Shared.Track)

local WorldService = {}

local TRACK = Config.Track

local function buildLighting()
	Lighting.Ambient = Color3.fromRGB(48, 44, 62)
	Lighting.OutdoorAmbient = Color3.fromRGB(58, 54, 74)
	Lighting.Brightness = 2
	Lighting.ClockTime = 15
	Lighting.EnvironmentDiffuseScale = 0.4
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.GlobalShadows = true

	for _, className in { "Atmosphere", "BloomEffect", "ColorCorrectionEffect" } do
		local existing = Lighting:FindFirstChildOfClass(className)
		if existing then
			existing:Destroy()
		end
	end

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.28
	atmosphere.Haze = 1.2
	atmosphere.Glare = 0.2
	atmosphere.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 1.1
	bloom.Size = 28
	bloom.Threshold = 0.85
	bloom.Parent = Lighting

	local color = Instance.new("ColorCorrectionEffect")
	color.Saturation = 0.2
	color.Contrast = 0.15
	color.Parent = Lighting
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

local function buildTrack(world, worldIndex: number, parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = world.Id
	folder.Parent = parent

	local origin = Track.origin(worldIndex)
	local length = Track.length() + 90
	local centerZ = length / 2 - 50

	Build.part({
		Name = "Podlaha",
		Size = Vector3.new(TRACK.Width, 4, length),
		Position = origin + Vector3.new(0, -2, centerZ),
		Color = Config.Theme.Panel,
		Material = Enum.Material.Concrete,
		Parent = folder,
	})

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

	for index = 1, TRACK.BarrierCount do
		buildBarrierFrame(world, worldIndex, index, folder)
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

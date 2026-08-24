--!strict
--[[
	Preview — 3D náhled peta přímo v seznamu.

	Barevný čtverec vedle jména říká jen barvu. `ViewportFrame` umí uvnitř
	UI vykreslit skutečný 3D objekt s vlastní kamerou a světlem — hráč tak
	v obchodě vidí přesně to, co mu poletí za zády.

	Dvě věci, které se u ViewportFrame dělají špatně a bolí to:

	  1. KAMERA MUSÍ BÝT UVNITŘ. `ViewportFrame.CurrentCamera` je vlastní
	     kamera, která musí být potomkem toho frame. Kdo tam dá kameru
	     z Workspace, kouká na prázdno.

	  2. SVĚTLO SVĚTA SEM NESVÍTÍ. Osvětlení řídí `LightColor` a
	     `Ambient` na samotném frame. Bez nastavení je objekt černý,
	     i když má jasnou barvu.

	Otáčení běží z jedné sdílené smyčky nad seznamem registrovaných
	náhledů — desítky vlastních connectionů by se při každém překreslení
	seznamu musely složitě rušit.
]]

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local Preview = {}

type Entry = {
	Frame: ViewportFrame,
	Model: BasePart,
	Camera: Camera,
	Distance: number,
	Phase: number,
}

local entries: { Entry } = {}
local elapsed = 0

local function shapeOf(shape: string): Enum.PartType
	if shape == "Ball" then
		return Enum.PartType.Ball
	elseif shape == "Cylinder" then
		return Enum.PartType.Cylinder
	end
	return Enum.PartType.Block
end

--[[
	Vyrobí náhled peta.

	`tier` odlišuje sloučené pety: dostanou kolem sebe prstenec, aby byl
	rozdíl vidět na první pohled, ne až z popisku.
]]
function Preview.pet(props: {
	Shape: string,
	Color: Color3,
	Tier: number?,
	Size: UDim2,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Parent: Instance?,
}): ViewportFrame
	local frame = Instance.new("ViewportFrame")
	frame.Name = "Preview"
	frame.Size = props.Size
	frame.Position = props.Position or UDim2.fromScale(0, 0)
	frame.AnchorPoint = props.AnchorPoint or Vector2.zero
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0

	-- Bez tohohle by byl objekt černý: světlo z Lightingu sem nesvítí
	frame.LightColor = Color3.new(1, 1, 1)
	frame.LightDirection = Vector3.new(-0.4, -1, -0.6)
	frame.Ambient = Config.Theme.PanelEdge
	frame.Parent = props.Parent

	local world = Instance.new("WorldModel")
	world.Parent = frame

	local part = Instance.new("Part")
	part.Shape = shapeOf(props.Shape)
	part.Size = Vector3.new(2, 2, 2)
	part.Color = props.Color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CFrame = CFrame.new()
	part.Parent = world

	-- Sloučený pet nese prstenec, aby byl rozdíl vidět bez čtení
	local tier = props.Tier or 0
	if tier > 0 then
		local ring = Instance.new("Part")
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.16, 3.4, 3.4)
		ring.Color = Config.Theme.Gold
		ring.Material = Enum.Material.Neon
		ring.Transparency = 0.25
		ring.Anchored = true
		ring.CanCollide = false
		ring.CFrame = CFrame.new() * CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = world
	end

	-- Kamera musí být potomkem frame, jinak se nevykreslí nic
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = frame
	frame.CurrentCamera = camera

	table.insert(entries, {
		Frame = frame,
		Model = part,
		Camera = camera,
		Distance = 6.5,
		-- Posun fáze, aby se celý seznam netočil jako jeden kus
		Phase = #entries * 0.7,
	})

	return frame
end

-- Zahozené náhledy vypadnou samy, až zmizí jejich frame
local function prune()
	for index = #entries, 1, -1 do
		if not entries[index].Frame.Parent then
			table.remove(entries, index)
		end
	end
end

function Preview.start()
	local sincePrune = 0

	RunService.RenderStepped:Connect(function(deltaTime)
		elapsed += deltaTime
		sincePrune += deltaTime

		for _, entry in entries do
			local angle = elapsed * 1.1 + entry.Phase
			local bob = math.sin(elapsed * 2 + entry.Phase) * 0.18

			-- Kamera obíhá objekt; točit objektem by u prstence rozbilo
			-- jeho orientaci vůči světlu
			local eye = Vector3.new(
				math.cos(angle) * entry.Distance,
				2 + bob,
				math.sin(angle) * entry.Distance
			)
			entry.Camera.CFrame = CFrame.lookAt(eye, Vector3.new(0, bob * 0.4, 0))
		end

		if sincePrune >= 2 then
			sincePrune = 0
			prune()
		end
	end)
end

return Preview

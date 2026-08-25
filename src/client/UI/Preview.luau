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
local Toy = require(Shared.Toy)

local Preview = {}

type Entry = {
	Frame: ViewportFrame,
	-- Model, ne díl: hračka je poskládaná z několika kusů
	Model: Instance,
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
	Vyrobí otáčející se náhled squishy hračky.

	Skládá se ze **stejného receptu**, jaký klient staví hráči do ruky
	(`Shared.Toy`). Kdyby měl náhled vlastní zjednodušenou verzi, měl
	by obchod postupem času jiné zboží než hra — a to je přesně ten
	druh rozdílu, kterého si nikdo nevšimne, dokud si hráč nestěžuje.

	Materiál je matný plast, ne Neon: v panelu má hračka vypadat stejně
	jako v ruce.
]]
function Preview.squishy(props: {
	Id: string?,
	Shape: string,
	Color: Color3,
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

	--[[
		Kusy visí na modelu, ne na sobě navzájem. Otáčí se pak celý
		model naráz a nemusí se přepočítávat žádný řetěz.
	]]
	local model = Instance.new("Model")
	model.Parent = world

	local NOMINAL = 2
	local recipe = Toy.pieces({ Id = props.Id, Shape = props.Shape, Color = props.Color })
	local root: BasePart? = nil
	local biggest = 0

	for index, piece in recipe do
		local size = piece.Size * NOMINAL
		local rotation = piece.Rotation or Vector3.zero

		local part = Instance.new("Part")
		part.Name = `Piece{index}`
		part.Shape = shapeOf(piece.Kind)
		part.Size = size
		part.Color = Toy.colorFor(piece.Role, props.Color, piece.Color)
		part.Material = Enum.Material.SmoothPlastic
		part.Reflectance = piece.Reflectance or 0.1
		part.Transparency = piece.Transparency or 0
		part.Anchored = true
		part.CanCollide = false
		part.CFrame = CFrame.new(piece.Offset * NOMINAL)
			* CFrame.Angles(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))
		part.Parent = model

		if piece.Label then
			local surface = Instance.new("SurfaceGui")
			surface.Face = (Enum.NormalId :: any)[piece.Label.Face] or Enum.NormalId.Front
			surface.CanvasSize = Vector2.new(200, 120)
			surface.LightInfluence = 0.6
			surface.Adornee = part
			surface.Parent = part

			local text = Instance.new("TextLabel")
			text.Size = UDim2.fromScale(0.86, 0.7)
			text.Position = UDim2.fromScale(0.07, 0.15)
			text.BackgroundTransparency = 1
			text.Font = Enum.Font.LuckiestGuy
			text.TextScaled = true
			text.TextColor3 = piece.Label.Color
			text.Text = piece.Label.Text
			text.Parent = surface
		end

		local volume = size.X * size.Y * size.Z
		if volume > biggest then
			biggest = volume
			root = part
		end
	end

	if root then
		model.PrimaryPart = root
	end

	-- Kamera musí být potomkem frame, jinak se nevykreslí nic
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = frame
	frame.CurrentCamera = camera

	table.insert(entries, {
		Frame = frame,
		Model = model,
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

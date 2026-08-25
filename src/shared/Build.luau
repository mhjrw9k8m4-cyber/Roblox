--!strict
--[[
	Build — pomocníky pro stavbu dílů a UI z kódu.
	Celý svět i rozhraní vzniká odsud, ve Studiu se nic neklikáš.
]]

local Build = {}

export type PartOptions = {
	Size: Vector3?,
	CFrame: CFrame?,
	Position: Vector3?,
	Color: Color3?,
	Material: Enum.Material?,
	Transparency: number?,
	Reflectance: number?,
	Anchored: boolean?,
	CanCollide: boolean?,
	CanQuery: boolean?,
	CanTouch: boolean?,
	CastShadow: boolean?,
	Shape: Enum.PartType?,
	--[[
		Povrch dílu. Tohle je ta věc, kvůli které vypadala hra plochá:
		všechno mělo `Smooth` a vycházely z toho hladké barevné kvádry.

		Roblox umí kreslit **nopy a důlky přímo na plochu dílu** a měřítko
		si dopočítá sám ze `Size` — velký díl dostane celou mřížku nopů
		zadarmo, bez jediného assetu a bez jediného dílu navíc. Přesně
		tímhle vypadají velké hry v žánru jako z kostek, ne jako z gumy.

		  `Surface`    — všechny strany naráz
		  `TopSurface` — jen vršek; na podlaze stačí ten
	]]
	Surface: Enum.SurfaceType?,
	TopSurface: Enum.SurfaceType?,
	Name: string?,
	Parent: Instance?,
}

function Build.part(options: PartOptions): Part
	local part = Instance.new("Part")
	part.Size = options.Size or Vector3.new(4, 1, 4)
	part.CFrame = options.CFrame or CFrame.new(options.Position or Vector3.zero)
	part.Color = options.Color or Color3.fromRGB(200, 200, 200)
	part.Material = options.Material or Enum.Material.SmoothPlastic
	part.Transparency = options.Transparency or 0
	part.Reflectance = options.Reflectance or 0
	part.Anchored = if options.Anchored == nil then true else options.Anchored
	part.CanCollide = if options.CanCollide == nil then true else options.CanCollide
	part.CanQuery = if options.CanQuery == nil then false else options.CanQuery
	part.CanTouch = if options.CanTouch == nil then false else options.CanTouch
	part.CastShadow = if options.CastShadow == nil then true else options.CastShadow
	local surface = options.Surface or Enum.SurfaceType.Smooth
	part.TopSurface = options.TopSurface or surface
	part.BottomSurface = surface
	part.LeftSurface = surface
	part.RightSurface = surface
	part.FrontSurface = surface
	part.BackSurface = surface
	part.Name = options.Name or "Part"

	if options.Shape then
		part.Shape = options.Shape
	end

	part.Parent = options.Parent
	return part
end

function Build.light(parent: BasePart, color: Color3, brightness: number, range: number): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = false
	light.Parent = parent
	return light
end

--[[
	Billboard s textem nad dílem. `AlwaysOnTop` je schválně volitelný —
	texty na bariérách musí být vidět skrz zeď, popisky ve světě ne.
]]
function Build.billboard(props: {
	Adornee: BasePart,
	Text: string,
	Size: UDim2,
	Offset: Vector3?,
	Color: Color3?,
	Font: Enum.Font?,
	AlwaysOnTop: boolean?,
	MaxDistance: number?,
}): (BillboardGui, TextLabel)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Info"
	billboard.Size = props.Size
	billboard.StudsOffsetWorldSpace = props.Offset or Vector3.zero
	billboard.AlwaysOnTop = props.AlwaysOnTop == true
	billboard.MaxDistance = props.MaxDistance or 300
	billboard.Adornee = props.Adornee
	billboard.LightInfluence = 0

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = props.Font or Enum.Font.FredokaOne
	label.Text = props.Text
	label.TextColor3 = props.Color or Color3.new(1, 1, 1)
	label.TextScaled = true
	label.RichText = true
	label.Parent = billboard

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(10, 10, 18)
	stroke.Thickness = 3
	stroke.Parent = label

	billboard.Parent = props.Adornee
	return billboard, label
end

-- Rychlé UI ---------------------------------------------------------------

function Build.corner(parent: GuiObject, radius: number): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

function Build.stroke(parent: GuiObject, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function Build.gradient(parent: GuiObject, from: Color3, to: Color3, rotation: number?): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(from, to)
	gradient.Rotation = rotation or 90
	gradient.Parent = parent
	return gradient
end

return Build

--!strict
--[[
	Build — pomocníky pro stavbu geometrie a UI z kódu.
	Díky nim se celý svět i rozhraní popisuje deklarativně
	a ve Studiu se nemusí nic klikat.
]]

local Config = require(script.Parent.Config)

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
	Shape: Enum.PartType?,
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
	part.CanQuery = if options.CanQuery == nil then true else options.CanQuery
	part.CanTouch = if options.CanTouch == nil then false else options.CanTouch
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Name = options.Name or "Part"

	if options.Shape then
		part.Shape = options.Shape
	end

	part.Parent = options.Parent
	return part
end

function Build.pointLight(parent: BasePart, color: Color3, brightness: number, range: number): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = false
	light.Parent = parent
	return light
end

-- Billboard s textem nad dílem
function Build.billboard(adornee: BasePart, text: string, size: UDim2, offset: Vector3): TextLabel
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Info"
	billboard.Size = size
	billboard.StudsOffsetWorldSpace = offset
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 160
	billboard.Adornee = adornee

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextColor3 = Config.Theme.Text
	label.TextStrokeTransparency = 0.5
	label.TextScaled = true
	label.RichText = true
	label.Parent = billboard

	billboard.Parent = adornee
	return label
end

-- Tvar objektu podle configu ("Block" | "Ball" | "Cylinder")
function Build.shapeOf(shape: string): Enum.PartType
	if shape == "Ball" then
		return Enum.PartType.Ball
	elseif shape == "Cylinder" then
		return Enum.PartType.Cylinder
	end
	return Enum.PartType.Block
end

-- Rychlé UI ---------------------------------------------------------------

function Build.corner(parent: GuiObject, radius: number): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

function Build.stroke(parent: GuiObject, color: Color3, thickness: number, transparency: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = transparency or 0
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

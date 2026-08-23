--!strict
--[[
	Widgets — stavební prvky rozhraní v "Roblox simulátor" stylu:
	tlustý tmavý obrys, výrazný gradient, kulaté rohy, tučné písmo.

	Všechno UI se skládá odsud, takže změna vzhledu na jednom místě
	projede celou hrou.
]]

local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Build = require(Shared.Build)
local Config = require(Shared.Config)

local Theme = Config.Theme

local Widgets = {}

-- Tenhle žánr má na všem stejně tlustý černý obrys — drží to vzhled pohromadě.
local OUTLINE = 3

-- UDim2 neumí násobení číslem, takže zvětšení se musí udělat po složkách.
local function scale(size: UDim2, factor: number): UDim2
	return UDim2.new(
		size.X.Scale * factor,
		size.X.Offset * factor,
		size.Y.Scale * factor,
		size.Y.Offset * factor
	)
end

function Widgets.panel(props: {
	Name: string?,
	Size: UDim2,
	Position: UDim2,
	AnchorPoint: Vector2?,
	Color: Color3?,
	Parent: Instance?,
	Radius: number?,
	Outline: boolean?,
}): Frame
	local frame = Instance.new("Frame")
	frame.Name = props.Name or "Panel"
	frame.Size = props.Size
	frame.Position = props.Position
	frame.AnchorPoint = props.AnchorPoint or Vector2.zero
	frame.BackgroundColor3 = props.Color or Theme.Panel
	frame.BorderSizePixel = 0
	frame.Parent = props.Parent

	Build.corner(frame, props.Radius or 12)
	if props.Outline ~= false then
		Build.stroke(frame, Theme.Outline, OUTLINE)
	end

	return frame
end

function Widgets.label(props: {
	Text: string,
	Size: UDim2,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Color: Color3?,
	Font: Enum.Font?,
	TextSize: number?,
	Align: Enum.TextXAlignment?,
	Parent: Instance?,
	Scaled: boolean?,
	Stroke: boolean?,
}): TextLabel
	local label = Instance.new("TextLabel")
	label.Text = props.Text
	label.Size = props.Size
	label.Position = props.Position or UDim2.fromScale(0, 0)
	label.AnchorPoint = props.AnchorPoint or Vector2.zero
	label.BackgroundTransparency = 1
	label.TextColor3 = props.Color or Theme.Text
	label.Font = props.Font or Enum.Font.FredokaOne
	label.TextSize = props.TextSize or 18
	label.TextScaled = props.Scaled or false
	label.TextXAlignment = props.Align or Enum.TextXAlignment.Left
	label.RichText = true
	label.Parent = props.Parent

	if props.Stroke ~= false then
		local stroke = Instance.new("UIStroke")
		stroke.Color = Theme.Outline
		stroke.Thickness = 2
		stroke.Parent = label
	end

	return label
end

--[[
	Tlačítko s gradientem a "zmáčknutím". Barva se drží v atributu, aby ji
	šlo měnit i po vytvoření (koupeno / nedostupné) a hover se pořád vracel
	na tu správnou.
]]
function Widgets.button(props: {
	Text: string,
	Size: UDim2,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Color: Color3?,
	TextColor: Color3?,
	TextSize: number?,
	Parent: Instance?,
	Radius: number?,
	Scaled: boolean?,
}): TextButton
	local base = props.Color or Theme.Accent

	local button = Instance.new("TextButton")
	button.Text = props.Text
	button.Size = props.Size
	button.Position = props.Position or UDim2.fromScale(0, 0)
	button.AnchorPoint = props.AnchorPoint or Vector2.zero
	button.BackgroundColor3 = base
	button.TextColor3 = props.TextColor or Color3.new(1, 1, 1)
	button.Font = Enum.Font.FredokaOne
	button.TextSize = props.TextSize or 18
	button.TextScaled = props.Scaled or false
	button.TextXAlignment = Enum.TextXAlignment.Center
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.RichText = true
	button.Parent = props.Parent

	Build.corner(button, props.Radius or 12)
	Build.gradient(button, Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190))

	-- Obrys rámečku je UIStroke, obrys písma vestavěná vlastnost. Dvě
	-- UIStroke na jednom prvku by se přebíjely.
	Build.stroke(button, Theme.Outline, OUTLINE)
	button.TextStrokeColor3 = Theme.Outline
	button.TextStrokeTransparency = 0

	button:SetAttribute("BaseColor", base)

	local function tweenTo(color: Color3, factor: number)
		TweenService:Create(button, TweenInfo.new(0.1), { BackgroundColor3 = color }):Play()
		TweenService:Create(button, TweenInfo.new(0.1), { Size = scale(props.Size, factor) }):Play()
	end

	button.MouseEnter:Connect(function()
		local current = button:GetAttribute("BaseColor") :: Color3
		tweenTo(current:Lerp(Color3.new(1, 1, 1), 0.2), 1.03)
	end)
	button.MouseLeave:Connect(function()
		tweenTo(button:GetAttribute("BaseColor") :: Color3, 1)
	end)
	button.MouseButton1Down:Connect(function()
		tweenTo((button:GetAttribute("BaseColor") :: Color3):Lerp(Color3.new(0, 0, 0), 0.15), 0.96)
	end)
	button.MouseButton1Up:Connect(function()
		tweenTo(button:GetAttribute("BaseColor") :: Color3, 1.03)
	end)

	return button
end

function Widgets.setColor(button: TextButton, color: Color3)
	button:SetAttribute("BaseColor", color)
	button.BackgroundColor3 = color
end

-- Velké čtvercové tlačítko s ikonou a popiskem (levý sloupec menu)
function Widgets.iconButton(props: {
	Icon: string,
	Text: string,
	Color: Color3,
	Size: UDim2,
	Parent: Instance?,
	LayoutOrder: number?,
}): TextButton
	local button = Widgets.button({
		Text = "",
		Size = props.Size,
		Color = props.Color,
		Parent = props.Parent,
		Radius = 14,
	})
	button.LayoutOrder = props.LayoutOrder or 1

	Widgets.label({
		Text = props.Icon,
		Size = UDim2.new(1, 0, 0.58, 0),
		Position = UDim2.fromScale(0, 0.04),
		Align = Enum.TextXAlignment.Center,
		Scaled = true,
		Parent = button,
		Stroke = false,
	})

	Widgets.label({
		Text = props.Text,
		Size = UDim2.new(1, -6, 0.3, 0),
		Position = UDim2.new(0, 3, 0.64, 0),
		Align = Enum.TextXAlignment.Center,
		Scaled = true,
		Parent = button,
	})

	return button
end

function Widgets.progressBar(props: {
	Size: UDim2,
	Position: UDim2,
	AnchorPoint: Vector2?,
	Color: Color3,
	Parent: Instance?,
}): (Frame, Frame)
	local track = Instance.new("Frame")
	track.Size = props.Size
	track.Position = props.Position
	track.AnchorPoint = props.AnchorPoint or Vector2.zero
	track.BackgroundColor3 = Theme.Background
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Parent = props.Parent
	Build.corner(track, 10)
	Build.stroke(track, Theme.Outline, OUTLINE)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = props.Color
	fill.BorderSizePixel = 0
	fill.Parent = track
	Build.corner(fill, 10)
	Build.gradient(fill, props.Color:Lerp(Color3.new(1, 1, 1), 0.3), props.Color)

	return track, fill
end

function Widgets.setProgress(fill: Frame, ratio: number)
	TweenService:Create(fill, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
		Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1),
	}):Play()
end

function Widgets.list(parent: Instance, padding: number, direction: Enum.FillDirection?): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, padding)
	layout.FillDirection = direction or Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = parent
	return layout
end

--[[
	Krátké "pumpnutí" prvku. Původní velikost se schová do atributu —
	kdyby se četla z prvku, rychlé opakované volání by si násobilo už
	zvětšenou velikost a prvek by rostl do nekonečna.
]]
function Widgets.pop(object: GuiObject, factor: number?)
	local original = object:GetAttribute("PopSize") :: UDim2?
	if not original then
		original = object.Size
		object:SetAttribute("PopSize", original)
	end

	object.Size = scale(original :: UDim2, factor or 1.12)
	TweenService:Create(object, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = original,
	}):Play()
end

return Widgets

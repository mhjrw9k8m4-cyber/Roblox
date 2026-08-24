--!strict
--[[
	Widgets — hotové komponenty poskládané ze `Style`.

	Každá z nich odpovídá něčemu, co je vidět na referencích:
	  panel     — okno se stud texturou a dvojitým obrysem
	  card      — barevný řádek seznamu
	  chip      — pilulka "ikona + hodnota" (cena, trofej, gem)
	  tile      — čtvercová ikona s popiskovou lištou (levé menu)
	  promo     — výrazná nabídka s gradientem (pravý sloupec)
	  bar       — tan/zlatá lišta postupu
	  bigNumber — obří číslo s tlustým obrysem
]]

local TweenService = game:GetService("TweenService")

local Style = require(script.Parent.Style)

local Theme = Style.Palette

local Widgets = {}

-- Zvětšení po složkách; UDim2 neumí násobení číslem
local function scale(size: UDim2, factor: number): UDim2
	return UDim2.new(
		size.X.Scale * factor,
		size.X.Offset * factor,
		size.Y.Scale * factor,
		size.Y.Offset * factor
	)
end

-- Text --------------------------------------------------------------------------

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
	Outline: number?,
}): TextLabel
	local label = Instance.new("TextLabel")
	label.Text = props.Text
	label.Size = props.Size
	label.Position = props.Position or UDim2.fromScale(0, 0)
	label.AnchorPoint = props.AnchorPoint or Vector2.zero
	label.BackgroundTransparency = 1
	label.TextColor3 = props.Color or Theme.Text
	label.Font = props.Font or Style.Font.Body
	label.TextSize = props.TextSize or 18
	label.TextScaled = props.Scaled or false
	label.TextXAlignment = props.Align or Enum.TextXAlignment.Left
	label.RichText = true
	label.Parent = props.Parent

	if props.Outline ~= 0 then
		Style.textOutline(label, props.Outline)
	end

	return label
end

-- Panel -----------------------------------------------------------------------------

function Widgets.panel(props: {
	Name: string?,
	Size: UDim2,
	Position: UDim2,
	AnchorPoint: Vector2?,
	Color: Color3?,
	Parent: Instance?,
	Radius: number?,
	Studs: boolean?,
	Bevel: boolean?,
	Lift: number?,
}): Frame
	local color = props.Color or Theme.Panel
	local radius = props.Radius or Style.Radius.Card

	local frame = Instance.new("Frame")
	frame.Name = props.Name or "Panel"
	frame.Size = props.Size
	frame.Position = props.Position
	frame.AnchorPoint = props.AnchorPoint or Vector2.zero
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.Parent = props.Parent

	Style.corner(frame, radius)
	Style.stroke(frame, Theme.Ink, Style.Outline.Thick)
	Style.gradient(frame, color, props.Lift or 0.18)

	if props.Studs then
		Style.studsWhenSized(frame)
	end
	if props.Bevel ~= false then
		Style.bevel(frame, Theme.PanelEdge, 5, radius)
	end

	return frame
end

-- Tlačítko ---------------------------------------------------------------------------

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
	local base = props.Color or Theme.Gold
	local radius = props.Radius or Style.Radius.Card

	local button = Instance.new("TextButton")
	button.Text = props.Text
	button.Size = props.Size
	button.Position = props.Position or UDim2.fromScale(0, 0)
	button.AnchorPoint = props.AnchorPoint or Vector2.zero
	button.BackgroundColor3 = base
	button.TextColor3 = props.TextColor or Style.contrast(base)
	button.Font = Style.Font.Body
	button.TextSize = props.TextSize or 18
	button.TextScaled = props.Scaled or false
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.RichText = true
	button.Parent = props.Parent

	Style.corner(button, radius)
	Style.stroke(button, Theme.Ink, Style.Outline.Thick)
	local gradient = Style.gradient(button, base, 0.22)
	Style.textOutline(button)

	button:SetAttribute("BaseColor", base)

	local function apply(color: Color3, factor: number)
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Style.lighten(color, 0.22)),
			ColorSequenceKeypoint.new(0.5, color),
			ColorSequenceKeypoint.new(1, Style.darken(color, 0.14)),
		})
		TweenService:Create(button, TweenInfo.new(0.09), { Size = scale(props.Size, factor) }):Play()
	end

	button.MouseEnter:Connect(function()
		apply(Style.lighten(button:GetAttribute("BaseColor") :: Color3, 0.12), 1.04)
	end)
	button.MouseLeave:Connect(function()
		apply(button:GetAttribute("BaseColor") :: Color3, 1)
	end)
	button.MouseButton1Down:Connect(function()
		apply(Style.darken(button:GetAttribute("BaseColor") :: Color3, 0.12), 0.95)
	end)
	button.MouseButton1Up:Connect(function()
		apply(button:GetAttribute("BaseColor") :: Color3, 1.04)
	end)

	return button
end

function Widgets.setColor(button: TextButton, color: Color3)
	button:SetAttribute("BaseColor", color)
	button.BackgroundColor3 = color
	button.TextColor3 = Style.contrast(color)

	local gradient = button:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Style.lighten(color, 0.22)),
			ColorSequenceKeypoint.new(0.5, color),
			ColorSequenceKeypoint.new(1, Style.darken(color, 0.14)),
		})
	end
end

-- Chip: pilulka "ikona + hodnota" -----------------------------------------------------

function Widgets.chip(props: {
	Icon: string,
	Text: string,
	Color: Color3,
	Size: UDim2,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Parent: Instance?,
	TextSize: number?,
}): (Frame, TextLabel)
	local frame = Widgets.panel({
		Name = "Chip",
		Size = props.Size,
		Position = props.Position or UDim2.fromScale(0, 0),
		AnchorPoint = props.AnchorPoint,
		Color = props.Color,
		Radius = Style.Radius.Chip,
		Bevel = false,
		Parent = props.Parent,
	})

	Widgets.label({
		Text = props.Icon,
		Size = UDim2.new(0, 30, 1, 0),
		Position = UDim2.new(0, 6, 0, 0),
		Align = Enum.TextXAlignment.Center,
		TextSize = (props.TextSize or 20) + 2,
		Parent = frame,
		Outline = 0,
	})

	local value = Widgets.label({
		Text = props.Text,
		Size = UDim2.new(1, -44, 1, 0),
		Position = UDim2.new(0, 38, 0, 0),
		Color = Style.contrast(props.Color),
		TextSize = props.TextSize or 20,
		Parent = frame,
	})

	return frame, value
end

-- Dlaždice levého menu ------------------------------------------------------------------

--[[
	Ikona nahoře, popisková lišta dole — přesně jako Rebirth / Teleport /
	Inventory v referenci. Popisek má vlastní tmavší pruh, jinak by se
	na barevném podkladu ztratil.
]]
function Widgets.tile(props: {
	Icon: string,
	Text: string,
	Color: Color3,
	Size: UDim2,
	Parent: Instance?,
	LayoutOrder: number?,
	-- kolik místa nechat nahoře, když má dlaždice ještě odznak nebo odpočet
	IconInset: number?,
}): TextButton
	local button = Widgets.button({
		Text = "",
		Size = props.Size,
		Color = props.Color,
		Radius = Style.Radius.Tile,
		Parent = props.Parent,
	})
	button.LayoutOrder = props.LayoutOrder or 1

	local inset = props.IconInset or 0
	Widgets.label({
		Text = props.Icon,
		Size = UDim2.new(1, -10, 0.56, -inset),
		Position = UDim2.new(0, 5, 0, 4 + inset),
		Align = Enum.TextXAlignment.Center,
		Scaled = true,
		Parent = button,
		Outline = 0,
	})

	local strip = Instance.new("Frame")
	strip.Name = "Label"
	strip.Size = UDim2.new(1, -10, 0.3, 0)
	strip.Position = UDim2.new(0, 5, 1, -6)
	strip.AnchorPoint = Vector2.new(0, 1)
	strip.BackgroundColor3 = Style.darken(props.Color, 0.45)
	strip.BorderSizePixel = 0
	strip.Parent = button
	Style.corner(strip, 7)

	Widgets.label({
		Text = props.Text,
		Size = UDim2.new(1, -6, 1, -2),
		Position = UDim2.fromOffset(3, 1),
		Align = Enum.TextXAlignment.Center,
		Scaled = true,
		Parent = strip,
		Outline = 2,
	})

	return button
end

-- Promo karta pravého sloupce -------------------------------------------------------------

--[[
	Dvoubarevná nabídka: název nahoře, cena dole. Gradient jde napříč
	(rotace 25°), aby karta "zářila" a odlišila se od plochých tlačítek.
]]
function Widgets.promo(props: {
	Title: string,
	Subtitle: string,
	ColorA: Color3,
	ColorB: Color3,
	Size: UDim2,
	Parent: Instance?,
	LayoutOrder: number?,
}): (TextButton, TextLabel)
	local button = Widgets.button({
		Text = "",
		Size = props.Size,
		Color = props.ColorA,
		Radius = Style.Radius.Card,
		Parent = props.Parent,
	})
	button.LayoutOrder = props.LayoutOrder or 1

	local gradient = button:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Rotation = 25
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Style.lighten(props.ColorA, 0.18)),
			ColorSequenceKeypoint.new(0.55, props.ColorB),
			ColorSequenceKeypoint.new(1, Style.darken(props.ColorB, 0.2)),
		})
	end

	Widgets.label({
		Text = props.Title,
		Size = UDim2.new(1, -14, 0, 24),
		Position = UDim2.new(0, 7, 0, 6),
		Align = Enum.TextXAlignment.Center,
		TextSize = 20,
		Parent = button,
	})

	local subtitle = Widgets.label({
		Text = props.Subtitle,
		Size = UDim2.new(1, -14, 0, 20),
		Position = UDim2.new(0, 7, 0, 30),
		Align = Enum.TextXAlignment.Center,
		Color = Theme.Gems,
		TextSize = 17,
		Parent = button,
	})

	return button, subtitle
end

-- Lišta postupu ------------------------------------------------------------------------------

function Widgets.bar(props: {
	Size: UDim2,
	Position: UDim2,
	AnchorPoint: Vector2?,
	Color: Color3?,
	Parent: Instance?,
}): (Frame, Frame)
	local track = Widgets.panel({
		Name = "Bar",
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Color = Theme.BarDeep,
		Radius = Style.Radius.Chip,
		Bevel = false,
		Parent = props.Parent,
	})
	track.ClipsDescendants = true

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = props.Color or Theme.BarFill
	fill.BorderSizePixel = 0
	fill.Parent = track
	Style.corner(fill, Style.Radius.Chip)
	Style.gradient(fill, props.Color or Theme.BarFill, 0.3)

	return track, fill
end

function Widgets.setProgress(fill: Frame, ratio: number)
	TweenService:Create(fill, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
		Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1),
	}):Play()
end

-- Obří číslo -----------------------------------------------------------------------------------

function Widgets.bigNumber(props: {
	Text: string,
	Size: UDim2,
	Position: UDim2,
	AnchorPoint: Vector2?,
	Color: Color3,
	Parent: Instance?,
}): TextLabel
	local label = Widgets.label({
		Text = props.Text,
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Color = props.Color,
		Font = Style.Font.Display,
		Align = Enum.TextXAlignment.Center,
		Scaled = true,
		Parent = props.Parent,
		Outline = 6,
	})

	-- Lehký přechod dolů do sytější barvy, ať číslo nevypadá ploše
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, props.Color),
	})
	gradient.Parent = label

	return label
end

-- Rozvržení --------------------------------------------------------------------------------------

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
	Krátké "pumpnutí". Původní velikost se schová do atributu — kdyby se
	četla z prvku, rychlé opakované volání by si násobilo už zvětšenou
	velikost a prvek by rostl donekonečna.
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

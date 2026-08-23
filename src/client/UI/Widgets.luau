--!strict
--[[
	Widgets — základní stavební prvky rozhraní.

	Všechno UI se skládá odsud, takže změna zaoblení nebo barvy
	na jednom místě projede celou hrou.
]]

local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Build = require(Shared.Build)
local Config = require(Shared.Config)

local Widgets = {}

local Theme = Config.Theme

function Widgets.panel(props: {
	Name: string?,
	Size: UDim2,
	Position: UDim2,
	AnchorPoint: Vector2?,
	Color: Color3?,
	Parent: Instance?,
	Radius: number?,
	Transparency: number?,
}): Frame
	local frame = Instance.new("Frame")
	frame.Name = props.Name or "Panel"
	frame.Size = props.Size
	frame.Position = props.Position
	frame.AnchorPoint = props.AnchorPoint or Vector2.zero
	frame.BackgroundColor3 = props.Color or Theme.Panel
	frame.BackgroundTransparency = props.Transparency or 0.05
	frame.BorderSizePixel = 0
	frame.Parent = props.Parent

	Build.corner(frame, props.Radius or 14)
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
}): TextLabel
	local label = Instance.new("TextLabel")
	label.Text = props.Text
	label.Size = props.Size
	label.Position = props.Position or UDim2.fromScale(0, 0)
	label.AnchorPoint = props.AnchorPoint or Vector2.zero
	label.BackgroundTransparency = 1
	label.TextColor3 = props.Color or Theme.Text
	label.Font = props.Font or Enum.Font.GothamMedium
	label.TextSize = props.TextSize or 16
	label.TextScaled = props.Scaled or false
	label.TextXAlignment = props.Align or Enum.TextXAlignment.Left
	label.RichText = true
	label.Parent = props.Parent
	return label
end

function Widgets.button(props: {
	Text: string,
	Size: UDim2,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Color: Color3?,
	TextColor: Color3?,
	Font: Enum.Font?,
	TextSize: number?,
	Parent: Instance?,
	Radius: number?,
}): TextButton
	local button = Instance.new("TextButton")
	button.Text = props.Text
	button.Size = props.Size
	button.Position = props.Position or UDim2.fromScale(0, 0)
	button.AnchorPoint = props.AnchorPoint or Vector2.zero
	button.BackgroundColor3 = props.Color or Theme.Accent
	button.TextColor3 = props.TextColor or Color3.new(1, 1, 1)
	button.Font = props.Font or Enum.Font.GothamBold
	button.TextSize = props.TextSize or 16
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.RichText = true
	button.Parent = props.Parent

	Build.corner(button, props.Radius or 10)

	-- Jemná odezva na najetí a stisk; bez ní působí UI mrtvě.
	local base = button.BackgroundColor3
	local hover = base:Lerp(Color3.new(1, 1, 1), 0.15)

	button.MouseEnter:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = hover }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = button:GetAttribute("BaseColor") or base }):Play()
	end)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.08), { Size = props.Size - UDim2.fromOffset(4, 4) }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), { Size = props.Size }):Play()
	end)

	button:SetAttribute("BaseColor", base)
	return button
end

function Widgets.progressBar(props: {
	Size: UDim2,
	Position: UDim2,
	AnchorPoint: Vector2?,
	Color: Color3,
	Parent: Instance?,
	Background: Color3?,
}): (Frame, Frame)
	local track = Instance.new("Frame")
	track.Size = props.Size
	track.Position = props.Position
	track.AnchorPoint = props.AnchorPoint or Vector2.zero
	track.BackgroundColor3 = props.Background or Theme.Background
	track.BackgroundTransparency = 0.25
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Parent = props.Parent
	Build.corner(track, 8)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = props.Color
	fill.BorderSizePixel = 0
	fill.Parent = track
	Build.corner(fill, 8)

	return track, fill
end

function Widgets.setProgress(fill: Frame, ratio: number, animate: boolean?)
	local target = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
	if animate == false then
		fill.Size = target
	else
		TweenService:Create(fill, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { Size = target }):Play()
	end
end

-- Svislý/vodorovný seznam s mezerami
function Widgets.list(parent: Instance, padding: number, direction: Enum.FillDirection?): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, padding)
	layout.FillDirection = direction or Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = parent
	return layout
end

return Widgets

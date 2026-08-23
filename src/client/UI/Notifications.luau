--!strict
--[[
	Notifications — krátké zprávy vlevo dole, mimo sloupce s tlačítky.
	Nové přibývají odspodu, staré samy odjedou.
]]

local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local Widgets = require(script.Parent.Widgets)

local Theme = Config.Theme

local COLORS = {
	success = Theme.Success,
	warn = Theme.Accent,
	error = Theme.Danger,
	info = Theme.Power,
}

local Notifications = {}
Notifications.__index = Notifications

export type Handle = typeof(setmetatable({} :: any, Notifications))

function Notifications.new(screen: ScreenGui): Handle
	local self = setmetatable({}, Notifications)

	local holder = Instance.new("Frame")
	holder.Name = "Toasts"
	holder.Size = UDim2.new(0, 340, 0, 260)
	holder.Position = UDim2.new(0, 14, 1, -110)
	holder.AnchorPoint = Vector2.new(0, 1)
	holder.BackgroundTransparency = 1
	holder.Parent = screen

	local layout = Widgets.list(holder, 8)
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left

	self.Holder = holder
	self.Counter = 0

	return self
end

function Notifications:push(text: string, kind: string?)
	self.Counter += 1
	local color = COLORS[kind or "info"] or Theme.Power

	local card = Widgets.panel({
		Name = "Toast",
		Size = UDim2.new(0, 330, 0, 54),
		Position = UDim2.fromScale(0, 0),
		Parent = self.Holder,
	})
	card.LayoutOrder = self.Counter

	local stripe = Widgets.panel({
		Size = UDim2.new(0, 6, 1, -16),
		Position = UDim2.new(0, 8, 0, 8),
		Color = color,
		Radius = 4,
		Outline = false,
		Parent = card,
	})

	local label = Widgets.label({
		Text = text,
		Size = UDim2.new(1, -32, 1, -10),
		Position = UDim2.new(0, 24, 0, 5),
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		Parent = card,
		Stroke = false,
	})
	label.TextWrapped = true

	-- Vjezd zleva
	card.Position = UDim2.new(0, -40, 0, 0)
	TweenService:Create(card, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, 0, 0, 0),
	}):Play()

	task.delay(4.5, function()
		if not card.Parent then
			return
		end

		local fade = TweenInfo.new(0.25)
		TweenService:Create(card, fade, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
		TweenService:Create(stripe, fade, { BackgroundTransparency = 1 }):Play()

		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
		end

		task.wait(0.3)
		card:Destroy()
	end)
end

return Notifications

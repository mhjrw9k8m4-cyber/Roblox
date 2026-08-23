--!strict
--[[
	Notifications — krátké zprávy v pravém dolním rohu.
	Nové přibývají odspodu, staré samy odjedou.
]]

local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Build = require(Shared.Build)
local Config = require(Shared.Config)

local Widgets = require(script.Parent.Widgets)

local Theme = Config.Theme

local COLORS = {
	success = Theme.Success,
	warn = Theme.Gold,
	error = Theme.Danger,
	info = Theme.Accent2,
}

local Notifications = {}
Notifications.__index = Notifications

export type Handle = typeof(setmetatable({} :: any, Notifications))

function Notifications.new(screen: ScreenGui): Handle
	local self = setmetatable({}, Notifications)

	local holder = Instance.new("Frame")
	holder.Name = "Zprávy"
	holder.Size = UDim2.new(0, 320, 0, 300)
	-- vlevo od sloupce tlačítek, ať se nepřekrývají
	holder.Position = UDim2.new(1, -164, 1, -24)
	holder.AnchorPoint = Vector2.new(1, 1)
	holder.BackgroundTransparency = 1
	holder.Parent = screen

	local layout = Widgets.list(holder, 8)
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right

	self.Holder = holder
	self.Counter = 0

	return self
end

function Notifications:push(text: string, kind: string?)
	self.Counter += 1

	local color = COLORS[kind or "info"] or Theme.Accent2

	local card = Widgets.panel({
		Name = "Zpráva",
		Size = UDim2.new(0, 300, 0, 52),
		Position = UDim2.fromScale(0, 0),
		Color = Theme.Panel,
		Transparency = 0.05,
		Radius = 10,
		Parent = self.Holder,
	})
	card.LayoutOrder = self.Counter
	Build.stroke(card, color, 2, 0.25)

	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(0, 5, 1, -14)
	stripe.Position = UDim2.new(0, 8, 0, 7)
	stripe.BackgroundColor3 = color
	stripe.BorderSizePixel = 0
	stripe.Parent = card
	Build.corner(stripe, 3)

	local label = Widgets.label({
		Text = text,
		Size = UDim2.new(1, -30, 1, -10),
		Position = UDim2.new(0, 22, 0, 5),
		TextSize = 15,
		Parent = card,
	})
	label.TextWrapped = true

	-- Vjezd zprava
	card.Position = UDim2.new(0, 40, 0, 0)
	TweenService:Create(card, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, 0, 0, 0),
	}):Play()

	task.delay(4, function()
		if not card.Parent then
			return
		end
		local fade = TweenInfo.new(0.25)
		TweenService:Create(card, fade, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
		TweenService:Create(stripe, fade, { BackgroundTransparency = 1 }):Play()
		task.wait(0.3)
		card:Destroy()
	end)
end

return Notifications

--!strict
--[[
	Panels — jedno okno pro upgrady, světy, tituly i rebirth.

	Všechny záložky sdílejí stejný seznam řádků; liší se jen tím, co do
	řádku napíšou a co udělá tlačítko vpravo. Přidání položky do Configu
	se tak projeví v UI samo, bez dalšího kódu.
]]

local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)

local Widgets = require(script.Parent.Widgets)

local Theme = Config.Theme

local TITLES = {
	upgrades = "⚡  UPGRADES",
	worlds = "🌍  WORLDS",
	titles = "👑  TITLES",
	rebirth = "⭐  REBIRTH",
}

local Panels = {}
Panels.__index = Panels

export type Handle = typeof(setmetatable({} :: any, Panels))

function Panels.new(screen: ScreenGui): Handle
	local self = setmetatable({}, Panels)

	self.Screen = screen
	self.Kind = nil :: string?
	self.Profile = nil
	self.Callbacks = {} :: { [string]: (string) -> () }

	self:build()
	return self
end

function Panels:build()
	local shade = Instance.new("TextButton")
	shade.Name = "Shade"
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.45
	shade.BorderSizePixel = 0
	shade.Text = ""
	shade.AutoButtonColor = false
	shade.Visible = false
	-- Stín a okno jsou sourozenci; potomci okna se při ZIndexBehavior.Sibling
	-- kreslí nad rodičem sami, takže víc ZIndexů není potřeba.
	shade.ZIndex = 5
	shade.Parent = self.Screen
	shade.MouseButton1Click:Connect(function()
		self:close()
	end)
	self.Shade = shade

	local root = Widgets.panel({
		Name = "Window",
		Size = UDim2.new(0, 640, 0, 460),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Radius = 18,
		Parent = self.Screen,
	})
	root.Visible = false
	root.ZIndex = 6
	self.Root = root

	self.Title = Widgets.label({
		Text = "",
		Size = UDim2.new(1, -110, 0, 38),
		Position = UDim2.new(0, 20, 0, 14),
		TextSize = 28,
		Parent = root,
	})

	self.Subtitle = Widgets.label({
		Text = "",
		Size = UDim2.new(1, -110, 0, 20),
		Position = UDim2.new(0, 20, 0, 50),
		Color = Theme.TextDim,
		TextSize = 15,
		Parent = root,
	})

	local close = Widgets.button({
		Text = "✕",
		Size = UDim2.new(0, 42, 0, 42),
		Position = UDim2.new(1, -56, 0, 14),
		Color = Theme.Danger,
		TextSize = 22,
		Parent = root,
	})
	close.MouseButton1Click:Connect(function()
		self:close()
	end)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.Size = UDim2.new(1, -28, 1, -96)
	scroll.Position = UDim2.new(0, 14, 0, 82)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = Theme.PanelLight
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = root
	Widgets.list(scroll, 8)

	self.Scroll = scroll
end

-- Jeden řádek seznamu ---------------------------------------------------------

function Panels:row(order: number, props: {
	Swatch: Color3,
	Icon: string?,
	Title: string,
	Detail: string,
	ButtonText: string,
	ButtonColor: Color3,
	Enabled: boolean,
	OnClick: (() -> ())?,
})
	local row = Widgets.panel({
		Name = "Row",
		Size = UDim2.new(1, -10, 0, 78),
		Position = UDim2.fromScale(0, 0),
		Color = Theme.PanelLight,
		Parent = self.Scroll,
	})
	row.LayoutOrder = order

	local swatch = Widgets.panel({
		Size = UDim2.fromOffset(56, 56),
		Position = UDim2.new(0, 11, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Color = props.Swatch,
		Radius = 12,
		Parent = row,
	})

	if props.Icon then
		Widgets.label({
			Text = props.Icon,
			Size = UDim2.fromScale(1, 1),
			Align = Enum.TextXAlignment.Center,
			Scaled = true,
			Parent = swatch,
			Stroke = false,
		})
	end

	Widgets.label({
		Text = props.Title,
		Size = UDim2.new(1, -250, 0, 24),
		Position = UDim2.new(0, 78, 0, 13),
		TextSize = 19,
		Parent = row,
	})

	local detail = Widgets.label({
		Text = props.Detail,
		Size = UDim2.new(1, -250, 0, 32),
		Position = UDim2.new(0, 78, 0, 38),
		Color = Theme.TextDim,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		Parent = row,
		Stroke = false,
	})
	detail.TextWrapped = true

	local button = Widgets.button({
		Text = props.ButtonText,
		Size = UDim2.new(0, 156, 0, 48),
		Position = UDim2.new(1, -168, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Color = props.ButtonColor,
		TextSize = 16,
		Parent = row,
	})

	if not props.Enabled then
		button.TextTransparency = 0.35
		button.Active = false
	elseif props.OnClick then
		button.MouseButton1Click:Connect(props.OnClick)
	end

	return row
end

local function clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- Obsah záložek ------------------------------------------------------------------

function Panels:renderUpgrades()
	local profile = self.Profile

	for index, upgrade in Config.Upgrades do
		local level = profile.Upgrades[upgrade.Id] or 0
		local price = Config.upgradePrice(upgrade.Id, level)

		local text, color, enabled
		if not price then
			text, color, enabled = "MAX", Theme.Success, false
		elseif profile.Coins < price then
			text, color, enabled = `💰 {Format.short(price)}`, Theme.Panel, false
		else
			text, color, enabled = `💰 {Format.short(price)}`, Theme.Coins, true
		end

		self:row(index, {
			Swatch = Theme.Success,
			Icon = upgrade.Icon,
			Title = `{upgrade.Name}  <font color="#A39EC0">{level}/{upgrade.MaxLevel}</font>`,
			Detail = upgrade.Desc,
			ButtonText = text,
			ButtonColor = color,
			Enabled = enabled,
			OnClick = function()
				self:fire("BuyUpgrade", upgrade.Id)
			end,
		})
	end
end

function Panels:renderWorlds()
	local profile = self.Profile

	for index, world in Config.Worlds do
		local owned = profile.Worlds[world.Id] == true
		local current = profile.WorldIndex == index

		local text, color, enabled
		if current then
			text, color, enabled = "PLAYING", Theme.Success, false
		elseif owned then
			text, color, enabled = "ENTER", Theme.Power, true
		else
			local allowed = Economy.canBuyWorld(profile, world.Id)
			text = `💰 {Format.short(world.Price)}`
			color = if allowed then Theme.Coins else Theme.Panel
			enabled = allowed
		end

		self:row(index, {
			Swatch = world.Color,
			Title = world.Name,
			Detail = `Pickup +{Format.short(world.Pickup)}  ·  first wall {Format.short(Config.barrierPower(index, 1))} power  ·  {Format.short(Config.barrierCoins(index, 1))} 💰 per wall`,
			ButtonText = text,
			ButtonColor = color,
			Enabled = enabled,
			OnClick = function()
				if owned then
					self:fire("EnterWorld", tostring(index))
				else
					self:fire("BuyWorld", world.Id)
				end
			end,
		})
	end
end

function Panels:renderTitles()
	local profile = self.Profile

	for index, title in Config.Titles do
		local unlocked = profile.Smashes >= title.Smashes
		local equipped = profile.Title == title.Id

		local text, color, enabled
		if equipped then
			text, color, enabled = "EQUIPPED", Theme.Success, false
		elseif unlocked then
			text, color, enabled = "EQUIP", Theme.Power, true
		else
			text, color, enabled = `🔒 {Format.short(title.Smashes)}`, Theme.Panel, false
		end

		self:row(index, {
			Swatch = title.Color,
			Icon = "👑",
			Title = title.Name,
			Detail = if unlocked
				then "Unlocked — shows above your head."
				else `Smash {Format.short(title.Smashes - profile.Smashes)} more walls to unlock.`,
			ButtonText = text,
			ButtonColor = color,
			Enabled = enabled,
			OnClick = function()
				self:fire("EquipTitle", title.Id)
			end,
		})
	end
end

function Panels:renderRebirth()
	local profile = self.Profile
	local cost = Config.rebirthCost(profile.Rebirths)
	local allowed, reason = Economy.canRebirth(profile)
	local bonus = math.floor(Config.Rebirth.BonusPerRebirth * 100)

	self:row(1, {
		Swatch = Color3.fromRGB(255, 92, 160),
		Icon = "⭐",
		Title = `REBIRTH #{profile.Rebirths + 1}`,
		Detail = `+{bonus}% power and coins forever, +{Config.Rebirth.GemsPerRebirth} 💎. Now: {Format.multiplier(profile.RebirthMultiplier or 1)}`,
		ButtonText = if allowed then "REBIRTH!" else `💰 {Format.short(cost)}`,
		ButtonColor = if allowed then Color3.fromRGB(255, 92, 160) else Theme.Panel,
		Enabled = allowed,
		OnClick = function()
			self:fire("DoRebirth", "")
		end,
	})

	self:row(2, {
		Swatch = Theme.Panel,
		Icon = "⚠️",
		Title = "What resets",
		Detail = "Coins, upgrades, unlocked worlds and power. Gems, titles and total smashes stay.",
		ButtonText = "—",
		ButtonColor = Theme.Panel,
		Enabled = false,
	})

	self:row(3, {
		Swatch = Theme.Power,
		Icon = "📊",
		Title = "Your stats",
		Detail = `Walls smashed: {Format.full(profile.Smashes)}  ·  playtime: {Format.time(profile.Playtime)}  ·  {Format.short(profile.CoinsPerSecond or 0)} 💰/s`,
		ButtonText = "—",
		ButtonColor = Theme.Panel,
		Enabled = false,
	})

	if not allowed and reason then
		self:row(4, {
			Swatch = Theme.Danger,
			Icon = "🔒",
			Title = "Not yet",
			Detail = reason,
			ButtonText = "—",
			ButtonColor = Theme.Panel,
			Enabled = false,
		})
	end
end

-- Ovládání --------------------------------------------------------------------------

function Panels:fire(action: string, value: string)
	local callback = self.Callbacks[action]
	if callback then
		callback(value)
	end
end

function Panels:refresh()
	if not self.Kind or not self.Profile or not self.Root.Visible then
		return
	end

	clear(self.Scroll)
	self.Title.Text = TITLES[self.Kind] or ""

	if self.Kind == "upgrades" then
		self.Subtitle.Text = `Every +1 is worth {Format.short(self.Profile.PickupValue or 1)} power right now.`
		self:renderUpgrades()
	elseif self.Kind == "worlds" then
		self.Subtitle.Text = "Entering a world resets your power — every world starts from zero."
		self:renderWorlds()
	elseif self.Kind == "titles" then
		self.Subtitle.Text = `Walls smashed: {Format.full(self.Profile.Smashes)}`
		self:renderTitles()
	elseif self.Kind == "rebirth" then
		self.Subtitle.Text = "Reset your run for a permanent multiplier."
		self:renderRebirth()
	end
end

function Panels:open(kind: string)
	if self.Root.Visible and self.Kind == kind then
		self:close()
		return
	end

	self.Kind = kind
	self.Root.Visible = true
	self.Shade.Visible = true
	self.Root.Size = UDim2.new(0, 600, 0, 420)
	self:refresh()

	TweenService:Create(self.Root, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 640, 0, 460),
	}):Play()
end

function Panels:close()
	self.Root.Visible = false
	self.Shade.Visible = false
	self.Kind = nil
end

function Panels:setProfile(profile)
	self.Profile = profile
	self:refresh()
end

return Panels

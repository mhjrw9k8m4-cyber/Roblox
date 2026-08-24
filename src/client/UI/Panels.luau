--!strict
--[[
	Panels — okno ve stylu inventáře z referencí.

	Co dělá ten vzhled:
	  * stud textura na panelu a tildy kolem názvu (`~UPGRADES~`),
	  * řada záložek nahoře, aktivní je světlejší a má obrys,
	  * řádky obarvené podle položky, ne uniformně šedé — barva nese
	    informaci o tom, o co jde,
	  * cena jako chip pilulka s ikonou, ne holý text,
	  * u světů náhled barvy jako velký "swatch" vlevo.

	Záložky sdílejí jedno vykreslování řádků; každá jen říká, co do
	řádku napsat a co udělá tlačítko. Přidání položky do Configu se tak
	projeví samo.
]]

local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)

local Style = require(script.Parent.Style)
local Widgets = require(script.Parent.Widgets)

local Theme = Config.Theme

local TABS = {
	{ Id = "upgrades", Icon = "⚡", Text = "Upgrades" },
	{ Id = "worlds", Icon = "🌍", Text = "Worlds" },
	{ Id = "titles", Icon = "👑", Text = "Titles" },
	{ Id = "rebirth", Icon = "⭐", Text = "Rebirth" },
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
	self.Tabs = {} :: { [string]: TextButton }

	self:build()
	return self
end

function Panels:build()
	local shade = Instance.new("TextButton")
	shade.Name = "Shade"
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Theme.Ink
	shade.BackgroundTransparency = 0.4
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
		Size = UDim2.new(0, 680, 0, 500),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Radius = Style.Radius.Panel,
		Studs = true,
		Parent = self.Screen,
	})
	root.Visible = false
	root.ZIndex = 6
	self.Root = root

	-- Tildy kolem názvu jsou drobnost, ale je to podpis žánru
	self.Title = Widgets.label({
		Text = "",
		Size = UDim2.new(1, -120, 0, 44),
		Position = UDim2.new(0, 60, 0, 12),
		Align = Enum.TextXAlignment.Center,
		TextSize = 32,
		Parent = root,
		Outline = 5,
	})

	local close = Widgets.button({
		Text = "✕",
		Size = UDim2.fromOffset(46, 46),
		Position = UDim2.new(1, -60, 0, 12),
		Color = Theme.Danger,
		TextSize = 24,
		Parent = root,
	})
	close.MouseButton1Click:Connect(function()
		self:close()
	end)

	-- Řada záložek
	local tabs = Instance.new("Frame")
	tabs.Name = "Tabs"
	tabs.Size = UDim2.new(1, -40, 0, 44)
	tabs.Position = UDim2.new(0, 20, 0, 62)
	tabs.BackgroundTransparency = 1
	tabs.Parent = root
	Widgets.list(tabs, 8, Enum.FillDirection.Horizontal)

	for index, tab in TABS do
		local button = Widgets.button({
			Text = `{tab.Icon} {tab.Text}`,
			Size = UDim2.new(0, 148, 1, 0),
			Color = Theme.PanelDeep,
			TextSize = 18,
			Radius = Style.Radius.Chip,
			Parent = tabs,
		})
		button.LayoutOrder = index
		button.MouseButton1Click:Connect(function()
			self:switch(tab.Id)
		end)
		self.Tabs[tab.Id] = button
	end

	self.Subtitle = Widgets.label({
		Text = "",
		Size = UDim2.new(1, -40, 0, 20),
		Position = UDim2.new(0, 20, 0, 110),
		Align = Enum.TextXAlignment.Center,
		Color = Theme.TextDim,
		Font = Style.Font.Detail,
		TextSize = 15,
		Parent = root,
		Outline = 2,
	})

	-- Vnitřní tmavá vana, ve které seznam leží — bez ní řádky plavou
	local well = Widgets.panel({
		Name = "Well",
		Size = UDim2.new(1, -36, 1, -158),
		Position = UDim2.new(0, 18, 0, 136),
		Color = Theme.PanelDeep,
		Radius = Style.Radius.Card,
		Bevel = false,
		Lift = 0.06,
		Parent = root,
	})

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.Size = UDim2.new(1, -16, 1, -16)
	scroll.Position = UDim2.fromOffset(8, 8)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = Theme.PanelEdge
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = well
	Widgets.list(scroll, 8)

	self.Scroll = scroll
end

-- Řádek seznamu ---------------------------------------------------------------------

function Panels:row(order: number, props: {
	Color: Color3,
	Icon: string?,
	Title: string,
	Detail: string,
	Chips: { { Icon: string, Text: string, Color: Color3 } }?,
	ButtonText: string,
	ButtonColor: Color3,
	Enabled: boolean,
	OnClick: (() -> ())?,
})
	local row = Widgets.panel({
		Name = "Row",
		Size = UDim2.new(1, -12, 0, 86),
		Position = UDim2.fromScale(0, 0),
		Color = props.Color,
		Radius = Style.Radius.Card,
		Parent = self.Scroll,
	})
	row.LayoutOrder = order

	local textColor = Style.contrast(props.Color)

	-- Velký barevný swatch vlevo, jako náhled traileru v referenci
	local swatch = Widgets.panel({
		Size = UDim2.fromOffset(62, 62),
		Position = UDim2.new(0, 12, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Color = Style.darken(props.Color, 0.3),
		Radius = Style.Radius.Chip,
		Bevel = false,
		Parent = row,
	})

	if props.Icon then
		Widgets.label({
			Text = props.Icon,
			Size = UDim2.new(1, -8, 1, -8),
			Position = UDim2.fromOffset(4, 4),
			Align = Enum.TextXAlignment.Center,
			Scaled = true,
			Parent = swatch,
			Outline = 0,
		})
	end

	Widgets.label({
		Text = props.Title,
		Size = UDim2.new(1, -380, 0, 26),
		Position = UDim2.new(0, 86, 0, 12),
		Color = textColor,
		TextSize = 21,
		Parent = row,
	})

	local detail = Widgets.label({
		Text = props.Detail,
		Size = UDim2.new(1, -380, 0, 36),
		Position = UDim2.new(0, 86, 0, 40),
		Color = if textColor == Theme.Text then Theme.TextDim else Style.lighten(Theme.Ink, 0.35),
		Font = Style.Font.Detail,
		TextSize = 14,
		Parent = row,
		Outline = 0,
	})
	detail.TextWrapped = true

	-- Chip pilulky s cenou / požadavkem
	if props.Chips then
		local chips = Instance.new("Frame")
		chips.Size = UDim2.new(0, 116, 1, -20)
		chips.Position = UDim2.new(1, -286, 0, 10)
		chips.BackgroundTransparency = 1
		chips.Parent = row
		Widgets.list(chips, 4)

		for index, chip in props.Chips do
			local frame = Widgets.chip({
				Icon = chip.Icon,
				Text = chip.Text,
				Color = chip.Color,
				Size = UDim2.new(1, 0, 0, 30),
				Parent = chips,
				TextSize = 17,
			})
			frame.LayoutOrder = index
		end
	end

	local button = Widgets.button({
		Text = props.ButtonText,
		Size = UDim2.new(0, 158, 0, 54),
		Position = UDim2.new(1, -170, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Color = props.ButtonColor,
		TextSize = 17,
		Parent = row,
	})

	if not props.Enabled then
		button.TextTransparency = 0.3
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

-- Obsah záložek ----------------------------------------------------------------------

function Panels:renderUpgrades()
	local profile = self.Profile

	for index, upgrade in Config.Upgrades do
		local level = profile.Upgrades[upgrade.Id] or 0
		local price = Config.upgradePrice(upgrade.Id, level)

		local text, color, enabled
		if not price then
			text, color, enabled = "MAX", Theme.Success, false
		elseif profile.Coins < price then
			text, color, enabled = `💰 {Format.short(price)}`, Theme.PanelDeep, false
		else
			text, color, enabled = `💰 {Format.short(price)}`, Theme.Gold, true
		end

		self:row(index, {
			Color = Theme.Acid,
			Icon = upgrade.Icon,
			Title = upgrade.Name,
			Detail = upgrade.Desc,
			Chips = { { Icon = "📈", Text = `{level}/{upgrade.MaxLevel}`, Color = Theme.PanelDeep } },
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
			text, color, enabled = "ENTER", Theme.Cyan, true
		else
			local allowed = Economy.canBuyWorld(profile, world.Id)
			text = `💰 {Format.short(world.Price)}`
			color = if allowed then Theme.Gold else Theme.PanelDeep
			enabled = allowed
		end

		self:row(index, {
			Color = world.Color,
			Title = world.Name,
			Detail = `First wall needs {Format.short(Config.barrierPower(index, 1))} power. Entering resets your power to zero.`,
			Chips = {
				{ Icon = "⚡", Text = `+{Format.short(world.Pickup)}`, Color = Theme.PanelDeep },
				{ Icon = "💰", Text = Format.short(Config.barrierCoins(index, 1)), Color = Theme.PanelDeep },
			},
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
			text, color, enabled = "EQUIP", Theme.Cyan, true
		else
			text, color, enabled = "🔒 LOCKED", Theme.PanelDeep, false
		end

		self:row(index, {
			Color = title.Color,
			Icon = "👑",
			Title = title.Name,
			Detail = if unlocked
				then "Unlocked — shows above your head."
				else `Smash {Format.short(title.Smashes - profile.Smashes)} more walls.`,
			Chips = { { Icon = "💥", Text = Format.short(title.Smashes), Color = Theme.PanelDeep } },
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
		Color = Theme.Pink,
		Icon = "⭐",
		Title = `REBIRTH #{profile.Rebirths + 1}`,
		Detail = `+{bonus}% power and coins forever, +{Config.Rebirth.GemsPerRebirth} gems.`,
		Chips = {
			{ Icon = "⭐", Text = tostring(profile.Rebirths), Color = Theme.PanelDeep },
			{ Icon = "✖️", Text = Format.multiplier(profile.RebirthMultiplier or 1), Color = Theme.PanelDeep },
		},
		ButtonText = if allowed then "REBIRTH!" else `💰 {Format.short(cost)}`,
		ButtonColor = if allowed then Theme.Danger else Theme.PanelDeep,
		Enabled = allowed,
		OnClick = function()
			self:fire("DoRebirth", "")
		end,
	})

	self:row(2, {
		Color = Theme.PanelDeep,
		Icon = "⚠️",
		Title = "What resets",
		Detail = "Coins, upgrades, unlocked worlds and power. Gems, titles and total smashes stay.",
		ButtonText = "—",
		ButtonColor = Theme.PanelDeep,
		Enabled = false,
	})

	self:row(3, {
		Color = Theme.Cyan,
		Icon = "📊",
		Title = "Your stats",
		Detail = `Walls smashed: {Format.full(profile.Smashes)}  ·  playtime: {Format.time(profile.Playtime)}  ·  {Format.short(profile.CoinsPerSecond or 0)} coins/s`,
		ButtonText = "—",
		ButtonColor = Theme.PanelDeep,
		Enabled = false,
	})

	if not allowed and reason then
		self:row(4, {
			Color = Theme.Danger,
			Icon = "🔒",
			Title = "Not yet",
			Detail = reason,
			ButtonText = "—",
			ButtonColor = Theme.PanelDeep,
			Enabled = false,
		})
	end
end

-- Ovládání -----------------------------------------------------------------------------

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

	for id, button in self.Tabs do
		Widgets.setColor(button, if id == self.Kind then Theme.Violet else Theme.PanelDeep)
	end

	if self.Kind == "upgrades" then
		self.Title.Text = "~UPGRADES~"
		self.Subtitle.Text = `Every +1 is worth {Format.short(self.Profile.PickupValue or 1)} power right now.`
		self:renderUpgrades()
	elseif self.Kind == "worlds" then
		self.Title.Text = "~WORLDS~"
		self.Subtitle.Text = "Bigger worlds pay more, but every wall costs more power."
		self:renderWorlds()
	elseif self.Kind == "titles" then
		self.Title.Text = "~TITLES~"
		self.Subtitle.Text = `Walls smashed: {Format.full(self.Profile.Smashes)}`
		self:renderTitles()
	elseif self.Kind == "rebirth" then
		self.Title.Text = "~REBIRTH~"
		self.Subtitle.Text = "Reset your run for a permanent multiplier."
		self:renderRebirth()
	end
end

-- Přepnutí záložky uvnitř otevřeného okna. Narozdíl od `open` netoggluje —
-- kliknout na záložku, na které už jsi, nesmí okno zavřít.
function Panels:switch(kind: string)
	self.Kind = kind
	self:refresh()
end

function Panels:open(kind: string)
	if self.Root.Visible and self.Kind == kind then
		self:close()
		return
	end

	self.Kind = kind
	self.Root.Visible = true
	self.Shade.Visible = true
	self.Root.Size = UDim2.new(0, 620, 0, 450)
	self:refresh()

	TweenService:Create(self.Root, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 680, 0, 500),
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

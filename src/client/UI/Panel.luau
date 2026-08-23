--!strict
--[[
	Panel — jedno okno pro nože, materiály, vylepšení, odměny i rebirth.

	Všechny záložky sdílejí stejný seznam řádků; liší se jen tím,
	co do řádku napíšou a co udělá tlačítko vpravo. Díky tomu se dá
	přidat nový obsah do Configu a UI se o něj postará samo.
]]

local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Build = require(Shared.Build)
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)

local Widgets = require(script.Parent.Widgets)

local Theme = Config.Theme

local TITLES = {
	tools = "🔪  Nože",
	objects = "🧊  Materiály",
	upgrades = "⚡  Vylepšení",
	rewards = "🎁  Odměny za hraní",
	rebirth = "⭐  Rebirth",
}

local Panel = {}
Panel.__index = Panel

export type Handle = typeof(setmetatable({} :: any, Panel))

function Panel.new(screen: ScreenGui): Handle
	local self = setmetatable({}, Panel)

	self.Screen = screen
	self.Kind = nil :: string?
	self.Profile = nil
	self.Rewards = {}
	self.Callbacks = {} :: { [string]: (string | number) -> () }

	self:build()
	return self
end

function Panel:build()
	local root = Widgets.panel({
		Name = "Okno",
		Size = UDim2.new(0, 660, 0, 460),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Transparency = 0.02,
		Radius = 18,
		Parent = self.Screen,
	})
	root.Visible = false
	Build.stroke(root, Theme.PanelLight, 2, 0.2)
	self.Root = root

	self.Title = Widgets.label({
		Text = "",
		Size = UDim2.new(1, -120, 0, 40),
		Position = UDim2.new(0, 24, 0, 14),
		Font = Enum.Font.FredokaOne,
		TextSize = 28,
		Parent = root,
	})

	self.Subtitle = Widgets.label({
		Text = "",
		Size = UDim2.new(1, -120, 0, 20),
		Position = UDim2.new(0, 24, 0, 52),
		Color = Theme.TextDim,
		TextSize = 15,
		Parent = root,
	})

	local close = Widgets.button({
		Text = "✕",
		Size = UDim2.new(0, 40, 0, 40),
		Position = UDim2.new(1, -56, 0, 16),
		Color = Theme.PanelLight,
		TextSize = 20,
		Parent = root,
	})
	close.TextXAlignment = Enum.TextXAlignment.Center
	close.MouseButton1Click:Connect(function()
		self:close()
	end)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Seznam"
	scroll.Size = UDim2.new(1, -32, 1, -100)
	scroll.Position = UDim2.new(0, 16, 0, 86)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = Theme.PanelLight
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = root

	local layout = Widgets.list(scroll, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	self.Scroll = scroll
end

-- Jeden řádek seznamu ------------------------------------------------------

function Panel:row(order: number, props: {
	Swatch: Color3,
	Title: string,
	Detail: string,
	ButtonText: string,
	ButtonColor: Color3,
	Enabled: boolean,
	OnClick: (() -> ())?,
})
	local row = Widgets.panel({
		Name = "Řádek",
		Size = UDim2.new(1, -12, 0, 76),
		Position = UDim2.fromScale(0, 0),
		Color = Theme.PanelLight,
		Transparency = 0.15,
		Radius = 12,
		Parent = self.Scroll,
	})
	row.LayoutOrder = order

	local swatch = Instance.new("Frame")
	swatch.Size = UDim2.fromOffset(52, 52)
	swatch.Position = UDim2.new(0, 12, 0.5, 0)
	swatch.AnchorPoint = Vector2.new(0, 0.5)
	swatch.BackgroundColor3 = props.Swatch
	swatch.BorderSizePixel = 0
	swatch.Parent = row
	Build.corner(swatch, 10)
	Build.gradient(swatch, props.Swatch, props.Swatch:Lerp(Color3.new(0, 0, 0), 0.35))

	Widgets.label({
		Text = props.Title,
		Size = UDim2.new(1, -240, 0, 22),
		Position = UDim2.new(0, 76, 0, 14),
		Font = Enum.Font.GothamBold,
		TextSize = 17,
		Parent = row,
	})

	Widgets.label({
		Text = props.Detail,
		Size = UDim2.new(1, -240, 0, 32),
		Position = UDim2.new(0, 76, 0, 36),
		Color = Theme.TextDim,
		TextSize = 14,
		Parent = row,
	})

	local button = Widgets.button({
		Text = props.ButtonText,
		Size = UDim2.new(0, 140, 0, 44),
		Position = UDim2.new(1, -152, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Color = props.ButtonColor,
		TextSize = 15,
		Parent = row,
	})
	button.TextXAlignment = Enum.TextXAlignment.Center
	button.Active = props.Enabled
	button.AutoButtonColor = false

	if not props.Enabled then
		button.TextTransparency = 0.35
		button.BackgroundTransparency = 0.45
	elseif props.OnClick then
		button.MouseButton1Click:Connect(props.OnClick)
	end

	return row
end

local function clearChildren(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- Obsah jednotlivých záložek ------------------------------------------------

function Panel:renderTools()
	local profile = self.Profile

	for index, tool in Config.Tools do
		local owned = profile.Tools[tool.Id] == true
		local equipped = profile.EquippedTool == tool.Id
		local locked = profile.Level < tool.Level

		local buttonText, buttonColor, enabled
		if equipped then
			buttonText, buttonColor, enabled = "NASAZENO", Theme.Success, false
		elseif owned then
			buttonText, buttonColor, enabled = "Nasadit", Theme.Accent2, true
		elseif locked then
			buttonText, buttonColor, enabled = `🔒 Úroveň {tool.Level}`, Theme.Panel, false
		elseif profile.Coins < tool.Price then
			buttonText, buttonColor, enabled = `💰 {Format.short(tool.Price)}`, Theme.Panel, false
		else
			buttonText, buttonColor, enabled = `💰 {Format.short(tool.Price)}`, Theme.Gold, true
		end

		self:row(index, {
			Swatch = tool.Color,
			Title = tool.Name,
			Detail = `Poškození {Format.short(tool.Damage)}  ·  prodleva {string.format("%.2f", tool.Cooldown)}s`,
			ButtonText = buttonText,
			ButtonColor = buttonColor,
			Enabled = enabled,
			OnClick = function()
				if owned then
					self:fire("EquipTool", tool.Id)
				else
					self:fire("BuyTool", tool.Id)
				end
			end,
		})
	end
end

function Panel:renderObjects()
	local profile = self.Profile

	for index, object in Config.Objects do
		local owned = profile.Objects[object.Id] == true
		local equipped = profile.EquippedObject == object.Id
		local locked = profile.Level < object.Level

		local buttonText, buttonColor, enabled
		if equipped then
			buttonText, buttonColor, enabled = "KRÁJÍŠ", Theme.Success, false
		elseif owned then
			buttonText, buttonColor, enabled = "Přepnout", Theme.Accent2, true
		elseif locked then
			buttonText, buttonColor, enabled = `🔒 Úroveň {object.Level}`, Theme.Panel, false
		elseif profile.Coins < object.Price then
			buttonText, buttonColor, enabled = `💰 {Format.short(object.Price)}`, Theme.Panel, false
		else
			buttonText, buttonColor, enabled = `💰 {Format.short(object.Price)}`, Theme.Gold, true
		end

		self:row(index, {
			Swatch = object.Color,
			Title = object.Name,
			Detail = `Hodnota {Format.short(object.Value)} 💰  ·  odolnost {Format.short(object.Integrity)}  ·  {object.Xp} XP`,
			ButtonText = buttonText,
			ButtonColor = buttonColor,
			Enabled = enabled,
			OnClick = function()
				if owned then
					self:fire("EquipObject", object.Id)
				else
					self:fire("BuyObject", object.Id)
				end
			end,
		})
	end
end

function Panel:renderUpgrades()
	local profile = self.Profile

	for index, upgrade in Config.Upgrades do
		local level = profile.Upgrades[upgrade.Id] or 0
		local price = Config.upgradePrice(upgrade.Id, level)

		local buttonText, buttonColor, enabled
		if not price then
			buttonText, buttonColor, enabled = "MAX", Theme.Success, false
		elseif profile.Coins < price then
			buttonText, buttonColor, enabled = `💰 {Format.short(price)}`, Theme.Panel, false
		else
			buttonText, buttonColor, enabled = `💰 {Format.short(price)}`, Theme.Gold, true
		end

		self:row(index, {
			Swatch = Theme.Success,
			Title = `{upgrade.Icon}  {upgrade.Name}  <font color="#A39EC0">{level}/{upgrade.MaxLevel}</font>`,
			Detail = upgrade.Desc,
			ButtonText = buttonText,
			ButtonColor = buttonColor,
			Enabled = enabled,
			OnClick = function()
				self:fire("BuyUpgrade", upgrade.Id)
			end,
		})
	end
end

function Panel:renderRewards()
	for index, reward in self.Rewards do
		local buttonText, buttonColor, enabled
		if reward.Claimed then
			buttonText, buttonColor, enabled = "VYZVEDNUTO", Theme.Panel, false
		elseif reward.Ready then
			buttonText, buttonColor, enabled = "VYZVEDNOUT", Theme.Gold, true
		else
			buttonText, buttonColor, enabled = Format.time(reward.Remaining), Theme.Panel, false
		end

		self:row(index, {
			Swatch = if reward.Ready and not reward.Claimed then Theme.Gold else Theme.Panel,
			Title = `Odehráno {reward.Label}`,
			Detail = `Odměna {Format.short(reward.Coins)} 💰 (násobí se rebirthy)`,
			ButtonText = buttonText,
			ButtonColor = buttonColor,
			Enabled = enabled,
			OnClick = function()
				self:fire("ClaimReward", reward.Minutes)
			end,
		})
	end
end

function Panel:renderRebirth()
	local profile = self.Profile
	local cost = Config.rebirthCost(profile.Rebirths)
	local canAfford = profile.Coins >= cost
	local bonus = math.floor(Config.Rebirth.BonusPerRebirth * 100)

	self:row(1, {
		Swatch = Theme.Danger,
		Title = `Rebirth #{profile.Rebirths + 1}`,
		Detail = `Trvale +{bonus} % ke všem výdělkům. Aktuálně {Format.multiplier(Economy.rebirthMultiplier(profile))}.`,
		ButtonText = if canAfford then "REBIRTH!" else `💰 {Format.short(cost)}`,
		ButtonColor = if canAfford then Theme.Danger else Theme.Panel,
		Enabled = canAfford,
		OnClick = function()
			self:fire("DoRebirth", "")
		end,
	})

	local keepsTools = if Config.Rebirth.KeepTools then "Nože si necháváš." else "Nože se resetují."

	self:row(2, {
		Swatch = Theme.PanelLight,
		Title = "Co rebirth udělá",
		Detail = `Vynuluje peníze, vylepšení a odemčené materiály. {keepsTools}`,
		ButtonText = "—",
		ButtonColor = Theme.Panel,
		Enabled = false,
	})

	self:row(3, {
		Swatch = Theme.Accent2,
		Title = "Tvoje statistiky",
		Detail = `Ran celkem: {Format.full(profile.TotalStrikes)}  ·  rozbito: {Format.full(profile.TotalDestroyed)}  ·  odehráno: {Format.time(profile.Playtime)}`,
		ButtonText = "—",
		ButtonColor = Theme.Panel,
		Enabled = false,
	})
end

-- Ovládání -----------------------------------------------------------------

function Panel:fire(action: string, value: string | number)
	local callback = self.Callbacks[action]
	if callback then
		callback(value)
	end
end

function Panel:refresh()
	if not self.Kind or not self.Profile or not self.Root.Visible then
		return
	end

	clearChildren(self.Scroll)
	self.Title.Text = TITLES[self.Kind] or ""

	if self.Kind == "tools" then
		self.Subtitle.Text = "Silnější nůž = rychlejší rozpad materiálu."
		self:renderTools()
	elseif self.Kind == "objects" then
		self.Subtitle.Text = "Tvrdší materiál trvá dýl, ale nese mnohem víc."
		self:renderObjects()
	elseif self.Kind == "upgrades" then
		self.Subtitle.Text = `Příjem teď: {Format.short(self.Profile.CoinsPerSecond)} 💰/s`
		self:renderUpgrades()
	elseif self.Kind == "rewards" then
		self.Subtitle.Text = `Odehráno celkem: {Format.time(self.Profile.Playtime)}`
		self:renderRewards()
	elseif self.Kind == "rebirth" then
		self.Subtitle.Text = "Reset za trvalý násobič. Základ nekonečného grindu."
		self:renderRebirth()
	end
end

function Panel:open(kind: string)
	if self.Root.Visible and self.Kind == kind then
		self:close()
		return
	end

	self.Kind = kind
	self.Root.Visible = true
	self.Root.Size = UDim2.new(0, 620, 0, 420)
	self:refresh()

	TweenService:Create(self.Root, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 660, 0, 460),
	}):Play()
end

function Panel:close()
	self.Root.Visible = false
	self.Kind = nil
end

function Panel:setProfile(profile)
	self.Profile = profile
	self:refresh()
end

function Panel:setRewards(rewards)
	self.Rewards = rewards
	if self.Kind == "rewards" then
		self:refresh()
	end
end

return Panel

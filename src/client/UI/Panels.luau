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
local Combo = require(Shared.Combo)
local Cosmetics = require(Shared.Cosmetics)
local Format = require(Shared.Format)
local Live = require(Shared.Live)
local Perks = require(Shared.Perks)
local Rarity = require(Shared.Rarity)
local Zones = require(Shared.Zones)

local Layout = require(script.Parent.Layout)
local Preview = require(script.Parent.Preview)
local Style = require(script.Parent.Style)
local Widgets = require(script.Parent.Widgets)

local Theme = Config.Theme

local TABS = {
	{ Id = "upgrades", Icon = "⚡", Text = "Upgrades" },
	{ Id = "squishies", Icon = "🧸", Text = "Squishies" },
	{ Id = "daily", Icon = "📅", Text = "Daily" },
	{ Id = "worlds", Icon = "🌍", Text = "Worlds" },
	{ Id = "codes", Icon = "🎟️", Text = "Codes" },
	{ Id = "trade", Icon = "🔄", Text = "Trade" },
	{ Id = "style", Icon = "✨", Text = "Style" },
	{ Id = "titles", Icon = "👑", Text = "Titles" },
	{ Id = "rebirth", Icon = "⭐", Text = "Rebirth" },
	{ Id = "shop", Icon = "💎", Text = "Shop" },
	{ Id = "settings", Icon = "⚙️", Text = "Settings" },
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
	self.Retention = nil
	self.Offers = nil
	self.Trade = nil
	self.Invite = nil
	self.Candidates = {}

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

	--[[
		Okno je relativní ke obrazovce, ne pevné. Se stropem se na monitoru
		neroztáhne, s podlahou se na telefonu nesrazí pod čitelnost —
		a hlavně se vždycky vejde, což pevných 680×500 na mobilu nedělá.
	]]
	local root = Widgets.panel({
		Name = "Window",
		Size = UDim2.new(0.94, 0, 0.9, 0),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Radius = Style.Radius.Panel,
		Studs = true,
		Parent = self.Screen,
	})
	Layout.constrain(root, Vector2.new(680, 500), Vector2.new(420, 320))
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

	-- Řada záložek. Je jich devět, takže se musí dát posouvat —
	-- napevno naskládané by se na užší obrazovce ořízly.
	local tabs = Instance.new("ScrollingFrame")
	tabs.Name = "Tabs"
	tabs.Size = UDim2.new(1, -40, 0, 48)
	tabs.Position = UDim2.new(0, 20, 0, 62)
	tabs.BackgroundTransparency = 1
	tabs.BorderSizePixel = 0
	tabs.ScrollBarThickness = 3
	tabs.ScrollBarImageColor3 = Theme.PanelEdge
	tabs.ScrollingDirection = Enum.ScrollingDirection.X
	tabs.CanvasSize = UDim2.new()
	tabs.AutomaticCanvasSize = Enum.AutomaticSize.X
	tabs.Parent = root

	local tabLayout = Widgets.list(tabs, 8, Enum.FillDirection.Horizontal)
	tabLayout.VerticalAlignment = Enum.VerticalAlignment.Top

	for index, tab in TABS do
		local button = Widgets.button({
			Text = `{tab.Icon} {tab.Text}`,
			Size = UDim2.new(0, 128, 0, 42),
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

--[[
	Barva do RichText. `Color3:ToHex` na klientu existuje, ale tenhle
	tvar je čitelný i v testu, kde je Color3 jen tabulka.
]]
local function hex(color: Color3): string
	return string.format(
		"%02X%02X%02X",
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5)
	)
end

function Panels:row(order: number, props: {
	Color: Color3,
	--[[
		Id stupně vzácnosti. Pozadí řádky říká, o jaký druh obsahu jde,
		rámeček a štítek za jménem říkají, **kam v celé řadě** ta věc
		patří — a to je informace, kterou hráč do teď mohl získat jedině
		porovnáváním cen.
	]]
	Rarity: string?,
	Icon: string?,
	Title: string,
	Detail: string,
	Chips: { { Icon: string, Text: string, Color: Color3 } }?,
	-- Když je zadané, místo barevného čtverce se vykreslí 3D náhled
	Preview: { Id: string?, Shape: string, Color: Color3 }?,
	ButtonText: string,
	ButtonColor: Color3,
	Enabled: boolean,
	OnClick: (() -> ())?,
	Gradient: { Color3 }?,
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

	local tier = if props.Rarity then Rarity.byId(props.Rarity) else nil
	if tier then
		--[[
			Přebarvuje se stávající obrys, nepřidává se druhý: Roblox
			bere na jednom prvku jen první `UIStroke` a ten druhý by se
			tiše nevykreslil.
		]]
		local stroke = row:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = tier.Color
			stroke.Thickness = Style.Outline.Thick + 1
		end
	end

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

	-- Vícebarevný kus (stopa, aura) se pozná podle přechodu ve swatchi.
	if props.Gradient and #props.Gradient > 1 then
		local keypoints = {}
		local count = #props.Gradient
		for index, color in props.Gradient do
			table.insert(keypoints, ColorSequenceKeypoint.new((index - 1) / (count - 1), color))
		end

		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(keypoints)
		gradient.Rotation = 35
		gradient.Parent = swatch
	end

	if props.Preview then
		Preview.squishy({
			Id = props.Preview.Id,
			Shape = props.Preview.Shape,
			Color = props.Preview.Color,
			Size = UDim2.new(1, -4, 1, -4),
			Position = UDim2.fromOffset(2, 2),
			Parent = swatch,
		})
	elseif props.Icon then
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
		Text = if tier
			then `{props.Title}  <font color="#{hex(tier.Color)}" size="15">{tier.Name}</font>`
			else props.Title,
		Size = UDim2.new(1, -330, 0, 26),
		Position = UDim2.new(0, 86, 0, 12),
		Color = textColor,
		TextSize = 21,
		Parent = row,
	})

	local detail = Widgets.label({
		Text = props.Detail,
		Size = UDim2.new(1, -330, 0, 36),
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
		chips.Size = UDim2.new(0, 104, 1, -20)
		chips.Position = UDim2.new(1, -258, 0, 10)
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
		Size = UDim2.new(0, 142, 0, 54),
		Position = UDim2.new(1, -152, 0.5, 0),
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

		--[[
			Co hráč má teď a co bude mít po koupi. Bez toho nesla řádka
			jen statický popis a otázku "vyplatí se mi to?" hráč
			zodpovědět nemohl — číslo, které si kupuje, nikde nebylo
			vidět.
		]]
		local now = Config.upgradeEffect(upgrade.Id, level)
		local detail = if price
			then `{upgrade.Desc}\n{now}  →  {Config.upgradeEffect(upgrade.Id, level + 1)}`
			else `{upgrade.Desc}\n{now}  ·  maxed out`

		self:row(index, {
			Color = Theme.Acid,
			Rarity = Config.upgradeRarity(upgrade.Id).Id,
			Icon = upgrade.Icon,
			Title = upgrade.Name,
			Detail = detail,
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
			Rarity = Config.worldRarity(index).Id,
			Title = world.Name,
			Detail = `First wall needs {Format.short(Economy.barrierPower(profile, 1, index))} power. Entering resets your power to zero.`,
			Chips = {
				{ Icon = "⚡", Text = `+{Format.short(world.Pickup)}`, Color = Theme.PanelDeep },
				{ Icon = "💰", Text = Format.short(Economy.barrierCoins(profile, 1, index)), Color = Theme.PanelDeep },
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
			Rarity = Config.titleRarity(title.Id).Id,
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

--[[
	Stopy a aury. Odemykají se hraním, takže se u zamčených ukazuje,
	kolik ještě chybí — ne jen "LOCKED".

	Barvy kusu se kreslí přímo do ikony řádku pomocí UIGradientu, aby šlo
	poznat rozdíl bez toho, aby si to hráč musel nasadit.
]]
--[[
	Přepínač uvnitř záložky. Dvě tlačítka místo dvou dalších záložek nahoře:
	řada záložek už je dlouhá a na telefonu by se rozlámala.
]]
-- Klíč v profilu a ikona řádku podle druhu kosmetiky
local SLOTS = { trail = "Trail", aura = "Aura", skin = "Skin" }
local ICONS = { trail = "〰", aura = "✦", skin = "👤" }

function Panels:renderStyleSwitch(active: string)
	local holder = Instance.new("Frame")
	holder.Name = "StyleSwitch"
	holder.Size = UDim2.new(1, -12, 0, 44)
	holder.BackgroundTransparency = 1
	holder.LayoutOrder = 0
	holder.Parent = self.Scroll

	local options = { { Id = "trail", Text = "〰  TRAILS" }, { Id = "aura", Text = "✦  AURAS" } }

	for index, option in options do
		local button = Widgets.button({
			Text = option.Text,
			Size = UDim2.new(0.5, -4, 1, 0),
			Position = UDim2.new(0.5 * (index - 1), if index == 1 then 0 else 4, 0, 0),
			Color = if option.Id == active then Theme.Violet else Theme.PanelDeep,
			TextSize = 17,
			Parent = holder,
		})

		button.MouseButton1Click:Connect(function()
			self.StyleKind = option.Id
			self:refresh()
		end)
	end
end

function Panels:renderCosmetics(kind: string)
	local profile = self.Profile
	local equipped = (profile.Cosmetics or {})[SLOTS[kind]] or "none"
	local playtime = profile.Playtime

	for index, item in Cosmetics.list(kind) do
		local unlocked = Cosmetics.unlocked(profile, item, playtime)
		local have, need = Cosmetics.progress(profile, item, playtime)
		local look = if kind == "aura" then item.Aura else item.Trail
		local colors = look and look.Colors or { Theme.PanelDeep }

		local text, color, enabled
		if item.Id == equipped then
			text, color, enabled = "EQUIPPED", Theme.Success, false
		elseif unlocked then
			text, color, enabled = "EQUIP", Theme.Cyan, true
		else
			text, color, enabled = "🔒", Theme.PanelDeep, false
		end

		self:row(index, {
			Color = colors[1],
			--[[
				Vzácnost nese rámeček a štítek za jménem, stejně jako
				u zbytku hry. Chip s tím samým slovem vedle by říkal to
				samé dvakrát a bral místo číslu, které tam chybí.
			]]
			Rarity = item.Rarity,
			Icon = ICONS[kind] or "〰",
			Title = item.Name,
			Detail = if unlocked
				then Cosmetics.requirement(item)
				else `{Format.short(math.max(need - have, 0))} to go — {Cosmetics.requirement(item)}`,
			Gradient = colors,
			ButtonText = text,
			ButtonColor = color,
			Enabled = enabled,
			OnClick = function()
				self:fire("EquipCosmetic", `{kind}:{item.Id}`)
			end,
		})
	end
end

--[[
	Strom perků pod rebirthem.

	Větve nad hráčovým počtem rebirthů se schválně ukazují taky, jen
	zamčené — jinak by hráč nevěděl, na co se těší, a rebirth by pořád
	vypadal jako pouhé vynulování.
]]
function Panels:renderPerks(order: number): number
	local profile = self.Profile
	local tokens = Perks.available(profile)
	local index = order

	for _, perk in Perks.List do
		local level = Perks.level(profile, perk.Id)
		local cost = Perks.cost(perk, level)
		local allowed, reason = Perks.canBuy(profile, perk.Id)

		local text, color
		if not cost then
			text, color = "MAX", Theme.Success
		elseif allowed then
			text, color = `⭐ {cost}`, Theme.Gold
		else
			text, color = if reason == "Not enough tokens." then `⭐ {cost}` else "🔒", Theme.PanelDeep
		end

		self:row(index, {
			Color = if Perks.unlocked(profile, perk) then Theme.Violet else Theme.PanelDeep,
			Rarity = Perks.rarity(perk.Id).Id,
			Icon = perk.Icon,
			Title = perk.Name,
			Detail = if Perks.unlocked(profile, perk)
				then perk.Desc
				else `{perk.Desc}  ·  unlocks at {perk.Requires} rebirths`,
			Chips = {
				{ Icon = "📈", Text = `{level}/{perk.MaxLevel}`, Color = Theme.PanelDeep },
			},
			ButtonText = text,
			ButtonColor = color,
			Enabled = allowed,
			OnClick = function()
				self:fire("BuyPerk", perk.Id)
			end,
		})

		index += 1
	end

	return tokens
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

	self:renderPerks(5)
end

-- Squishy hračky -------------------------------------------------------------------

--[[
	Squishy hračky: co hráč vlastní i co si může koupit, v jednom seznamu.

	Zamčené se schválně ukazují taky. Prázdný seznam nic neslibuje;
	řada s cenou, na kterou zatím nemám, je důvod hrát dál.

	Kliknutí hračku vezme do ruky nebo odloží — dvě tlačítka na jedné
	kartě by byla přeplácaná a hráč stejně vždycky chce ten druhý stav.
]]
--[[
	Odkud hračka je. Level a hračka patří k sobě — v levelu stojí obří
	kus téhle hračky — jenže v seznamu to nebylo poznat, takže si hráč
	nemohl spojit řádek s tím, kolem čeho běžel.
]]
local function levelNote(toyId: string): string
	local zone, index = Zones.levelFor(toyId)
	if not zone or not index then
		return ""
	end

	return `  ·  level {index}: {zone.Name}`
end

function Panels:renderSquishies()
	local profile = self.Profile
	local list = profile.Squishies or {}
	local slots = profile.SquishySlots or 3

	local heldCount = 0
	for _, item in list do
		if item.Held then
			heldCount += 1
		end
	end

	for order, item in list do
		local grade = Live.Grades[item.Grade]
		local owned = item.Count > 0

		--[[
			Varianta přebíjí barvu třídy. Je vzácnější než třída a hráč
			ji musí poznat na první pohled — jinak by zlatá hračka
			vypadala v seznamu úplně stejně jako obyčejná a nemělo by
			smysl po ní jít.
		]]
		local variant = Live.variant(item.Variant)
		local color = if variant.Name ~= ""
			then variant.Color
			elseif grade
			then grade.Color
			else Theme.PanelDeep
		local full = heldCount >= slots and not item.Held

		--[[
			Hračka bez ceny se nekupuje — je to odměna. Tlačítko proto
			neříká "0 mincí", ale za co je; jinak by hráč čekal, že si
			ji koupí zadarmo.
		]]
		local buyable = item.Price > 0
		local affordable = buyable and profile.Coins >= item.Price

		local text, buttonColor, enabled
		if owned then
			text = if item.Held then "PUT AWAY" elseif full then `{heldCount}/{slots} FULL` else "HOLD"
			buttonColor = if item.Held then Theme.Success elseif full then Theme.PanelDeep else Theme.Cyan
			enabled = item.Held or not full
		elseif buyable then
			text = `💰 {Format.short(item.Price)}`
			buttonColor = if affordable then Theme.Gold else Theme.PanelDeep
			enabled = affordable
		else
			text = "REWARD"
			buttonColor = Theme.PanelDeep
			enabled = false
		end

		self:row(order, {
			Color = color,
			Rarity = Live.squishyRarity(item.Id).Id,
			Preview = { Id = item.Id, Shape = item.Shape, Color = item.Color },
			Title = if item.Count > 1
				then `{Live.variantName(item.Variant, item.Name)}  <font color="#2A1D46">×{item.Count}</font>`
				else Live.variantName(item.Variant, item.Name),
			Detail = `{item.Grade}  ·  +{math.floor(item.Power * variant.Multiplier * 100)}% power  ·  `
				.. `squeeze {math.floor(item.Squeeze * variant.Multiplier * 100)}%{levelNote(item.Id)}`,
			Chips = {
				{
					Icon = "⚡",
					Text = `+{math.floor(item.Power * variant.Multiplier * 100)}%`,
					Color = Theme.PanelDeep,
				},
			},
			ButtonText = text,
			ButtonColor = buttonColor,
			Enabled = enabled,
			OnClick = function()
				if owned then
					self:fire("HoldSquishy", item.Id)
				else
					self:fire("BuySquishy", item.Id)
				end
			end,
		})
	end
end

-- Denní odměna a úkoly ---------------------------------------------------------------

function Panels:renderDaily()
	local retention = self.Retention
	if not retention then
		self:row(1, {
			Color = Theme.PanelDeep,
			Title = "Loading…",
			Detail = "Fetching today's rewards.",
			ButtonText = "—",
			ButtonColor = Theme.PanelDeep,
			Enabled = false,
		})
		return
	end

	local daily = retention.Daily
	if daily then
		self:calendar(1, daily)
	end

	for index, quest in retention.Quests do
		local done = quest.Progress >= quest.Target
		self:questRow(index + 1, quest, done)
	end

	if retention.QuestStreak and retention.QuestStreak > 0 then
		self:row(#retention.Quests + 2, {
			Color = Theme.Acid,
			Icon = "🔥",
			Title = `Quest streak: {retention.QuestStreak}`,
			Detail = `Finish all {#retention.Quests} quests today to keep it and earn +{retention.StreakBonus} gems.`,
			ButtonText = "—",
			ButtonColor = Theme.PanelDeep,
			Enabled = false,
		})
	end

	self:sessionRow(#retention.Quests + 3, retention)
end

--[[
	Odměna za to, jak dlouho hráč v jednom sezení vydrží.

	Uděluje se sama, takže tady není tlačítko — je tu odpočet. Bez něj
	by hráč o téhle smyčce věděl jen z hlášky, která už proběhla,
	a "ještě chvilku" by mu nikdo nenabídl dopředu.
]]
function Panels:sessionRow(order: number, retention)
	local seconds = retention.Session or 0
	local done = retention.SessionTier or 0
	local next = Live.Playtime[done + 1]

	local detail, button
	if next then
		local left = math.max(next.Minutes * 60 - seconds, 0)
		detail = `Stay online for rewards. Next at {next.Minutes} min: +{next.Gems} 💎 and coins.`
		button = Format.time(left)
	else
		detail = "Every session reward claimed. Nice run."
		button = "ALL DONE"
	end

	self:row(order, {
		Color = Theme.Cyan,
		Icon = "⏱️",
		Title = `Session: {Format.time(seconds)}  ·  {done}/{#Live.Playtime}`,
		Detail = detail,
		ButtonText = button,
		ButtonColor = if next then Theme.PanelDeep else Theme.Success,
		Enabled = false,
	})
end

--[[
	Sedmidenní kolotoč jako pruh karet. Sedmý den je schválně větší —
	je to ta meta, kvůli které se hráč vrací celý týden.
]]
function Panels:calendar(order: number, daily)
	local card = Widgets.panel({
		Name = "Calendar",
		Size = UDim2.new(1, -12, 0, 150),
		Position = UDim2.fromScale(0, 0),
		Color = Theme.Violet,
		Radius = Style.Radius.Card,
		Parent = self.Scroll,
	})
	card.LayoutOrder = order

	Widgets.label({
		Text = if daily.Claimed
			then `Come back in {Format.time(daily.SecondsToNext)}`
			else `Day {daily.Day} is ready!`,
		Size = UDim2.new(1, -24, 0, 26),
		Position = UDim2.new(0, 12, 0, 8),
		TextSize = 20,
		Parent = card,
	})

	local strip = Instance.new("Frame")
	strip.Size = UDim2.new(1, -24, 0, 64)
	strip.Position = UDim2.new(0, 12, 0, 38)
	strip.BackgroundTransparency = 1
	strip.Parent = card
	Widgets.list(strip, 6, Enum.FillDirection.Horizontal)

	for _, entry in Live.Daily do
		local isToday = entry.Day == daily.Day and not daily.Claimed
		local passed = entry.Day < daily.Day or (entry.Day == daily.Day and daily.Claimed)

		local day = Widgets.panel({
			Size = UDim2.new(0, if entry.Day == 7 then 118 else 68, 1, 0),
			Position = UDim2.fromScale(0, 0),
			Color = if isToday then Theme.Gold elseif passed then Theme.PanelDeep else Theme.Panel,
			Radius = Style.Radius.Chip,
			Bevel = false,
			Parent = strip,
		})
		day.LayoutOrder = entry.Day

		Widgets.label({
			Text = if passed then "✓" else `DAY {entry.Day}`,
			Size = UDim2.new(1, -8, 0, 20),
			Position = UDim2.fromOffset(4, 6),
			Align = Enum.TextXAlignment.Center,
			Color = if isToday then Theme.Ink else Theme.Text,
			TextSize = 15,
			Parent = day,
		})

		Widgets.label({
			Text = if entry.Squishy then `💎{entry.Gems}\n🧸` else `💎{entry.Gems}`,
			Size = UDim2.new(1, -8, 0, 34),
			Position = UDim2.fromOffset(4, 26),
			Align = Enum.TextXAlignment.Center,
			Color = if isToday then Theme.Ink else Theme.Gems,
			TextSize = 15,
			Parent = day,
		})
	end

	local claim = Widgets.button({
		Text = if daily.Claimed
			then "CLAIMED"
			else `CLAIM  +{Format.short(daily.Coins)} 💰  +{daily.Gems} 💎`,
		Size = UDim2.new(1, -24, 0, 40),
		Position = UDim2.new(0, 12, 1, -48),
		Color = if daily.Claimed then Theme.PanelDeep else Theme.Acid,
		TextSize = 17,
		Parent = card,
	})

	if daily.Claimed then
		claim.Active = false
		claim.TextTransparency = 0.3
	else
		claim.MouseButton1Click:Connect(function()
			self:fire("ClaimDaily", "")
		end)
	end
end

function Panels:questRow(order: number, quest, done: boolean)
	local card = Widgets.panel({
		Name = "Quest",
		Size = UDim2.new(1, -12, 0, 78),
		Position = UDim2.fromScale(0, 0),
		Color = if quest.Claimed then Theme.PanelDeep elseif done then Theme.Acid else Theme.Panel,
		Radius = Style.Radius.Card,
		Parent = self.Scroll,
	})
	card.LayoutOrder = order

	local textColor = Style.contrast(if quest.Claimed then Theme.PanelDeep elseif done then Theme.Acid else Theme.Panel)

	Widgets.label({
		Text = quest.Text,
		Size = UDim2.new(1, -190, 0, 24),
		Position = UDim2.new(0, 14, 0, 10),
		Color = textColor,
		TextSize = 18,
		Parent = card,
	})

	local _, fill = Widgets.bar({
		Size = UDim2.new(1, -190, 0, 22),
		Position = UDim2.new(0, 14, 0, 40),
		Color = Theme.Cyan,
		Parent = card,
	})
	Widgets.setProgress(fill, quest.Progress / math.max(quest.Target, 1))

	Widgets.label({
		Text = `{Format.short(quest.Progress)} / {Format.short(quest.Target)}`,
		Size = UDim2.new(1, -190, 0, 22),
		Position = UDim2.new(0, 14, 0, 40),
		Align = Enum.TextXAlignment.Center,
		TextSize = 15,
		Parent = card,
	})

	local button = Widgets.button({
		Text = if quest.Claimed then "DONE" elseif done then `+{quest.Gems} 💎` else "IN PROGRESS",
		Size = UDim2.new(0, 158, 0, 50),
		Position = UDim2.new(1, -170, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Color = if quest.Claimed then Theme.PanelDeep elseif done then Theme.Gold else Theme.PanelDeep,
		TextSize = 16,
		Parent = card,
	})

	if quest.Claimed or not done then
		button.Active = false
		button.TextTransparency = 0.3
	else
		button.MouseButton1Click:Connect(function()
			self:fire("ClaimQuest", quest.Id)
		end)
	end
end

-- Kódy -------------------------------------------------------------------------------

function Panels:renderCodes()
	local card = Widgets.panel({
		Name = "CodeEntry",
		Size = UDim2.new(1, -12, 0, 112),
		Position = UDim2.fromScale(0, 0),
		Color = Theme.Violet,
		Radius = Style.Radius.Card,
		Parent = self.Scroll,
	})
	card.LayoutOrder = 1

	Widgets.label({
		Text = "Enter a code",
		Size = UDim2.new(1, -24, 0, 24),
		Position = UDim2.new(0, 12, 0, 8),
		TextSize = 19,
		Parent = card,
	})

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, -190, 0, 50)
	box.Position = UDim2.new(0, 12, 0, 40)
	box.BackgroundColor3 = Theme.PanelDeep
	box.BorderSizePixel = 0
	box.Font = Style.Font.Body
	box.PlaceholderText = "TYPE CODE HERE"
	box.PlaceholderColor3 = Theme.TextDim
	box.Text = ""
	box.TextColor3 = Theme.Text
	box.TextSize = 22
	box.ClearTextOnFocus = false
	box.Parent = card
	Style.corner(box, Style.Radius.Chip)
	Style.stroke(box, Theme.Ink, Style.Outline.Thick)

	local submit = Widgets.button({
		Text = "REDEEM",
		Size = UDim2.new(0, 158, 0, 50),
		Position = UDim2.new(1, -170, 0, 40),
		Color = Theme.Acid,
		TextSize = 18,
		Parent = card,
	})

	local function send()
		local code = box.Text
		if #code > 0 then
			box.Text = ""
			self:fire("RedeemCode", code)
		end
	end

	submit.MouseButton1Click:Connect(send)
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			send()
		end
	end)

	self:row(2, {
		Color = Theme.PanelDeep,
		Icon = "📺",
		Title = "Where to find codes",
		Detail = "New codes drop with every update and in videos about the game. Follow the group to get them first.",
		ButtonText = "—",
		ButtonColor = Theme.PanelDeep,
		Enabled = false,
	})
end

-- Placené nabídky -----------------------------------------------------------------------

function Panels:renderShop()
	local offers = self.Offers
	local profile = self.Profile
	local now = self:now()
	local order = 0

	-- Denní nabídka a směna jsou za herní měnu, takže se ukazují vždycky —
	-- i než někdo doplní ID gamepassů.
	local dealId = Economy.dealId(now)
	local deal = Config.boost(dealId)

	if deal then
		local price = Economy.boostPrice(dealId, now)
		order += 1
		self:row(order, {
			Color = Theme.Acid,
			Rarity = Config.boostRarity(dealId).Id,
			Icon = deal.Icon,
			Title = `TODAY ONLY — {deal.Name}`,
			Detail = `{math.floor(Live.Deal.Discount * 100)}% off for the rest of the day. Buying while it runs extends it, nothing is wasted.`,
			Chips = {
				{ Icon = "💎", Text = tostring(price), Color = Theme.Gems },
				{ Icon = "⏱️", Text = Format.time(deal.Duration), Color = Theme.PanelDeep },
			},
			ButtonText = `💎 {price}`,
			ButtonColor = if profile.Gems >= price then Theme.Gold else Theme.PanelDeep,
			Enabled = profile.Gems >= price,
			OnClick = function()
				self:fire("BuyBoost", dealId)
			end,
		})
	end

	do
		local value = Economy.exchangeValue(profile, now)
		local allowed = Economy.canExchange(profile)
		order += 1
		self:row(order, {
			Color = Theme.Cyan,
			Icon = "🔁",
			Title = "Trade gems for coins",
			Detail = `Worth {Format.time(Live.Exchange.Seconds)} of your current income, so the rate grows with you.`,
			Chips = {
				{ Icon = "💎", Text = tostring(Live.Exchange.Gems), Color = Theme.Gems },
				{ Icon = "💰", Text = Format.short(value), Color = Theme.Gold },
			},
			ButtonText = "TRADE",
			ButtonColor = if allowed then Theme.Gold else Theme.PanelDeep,
			Enabled = allowed,
			OnClick = function()
				self:fire("ExchangeGems", "")
			end,
		})
	end

	if not offers or (#offers.Passes == 0 and #offers.Products == 0) then
		self:row(order + 1, {
			Color = Theme.PanelDeep,
			Icon = "🛠️",
			Title = "Robux shop not set up yet",
			Detail = "Add gamepass and product IDs in src/shared/Live.luau. Until then nothing is shown here, so players never see a button that does nothing.",
			ButtonText = "—",
			ButtonColor = Theme.PanelDeep,
			Enabled = false,
		})
		return
	end

	for _, pass in offers.Passes do
		order += 1
		self:row(order, {
			Color = Theme.Violet,
			Icon = pass.Icon,
			Title = pass.Name,
			Detail = pass.Desc,
			ButtonText = if pass.Owned then "OWNED" else "BUY",
			ButtonColor = if pass.Owned then Theme.Success else Theme.Gold,
			Enabled = not pass.Owned,
			OnClick = function()
				self:fire("PromptPass", pass.Id)
			end,
		})
	end

	for _, product in offers.Products do
		order += 1
		self:row(order, {
			Color = Theme.Cyan,
			Icon = product.Icon,
			Title = product.Name,
			Detail = "One-time purchase.",
			ButtonText = "BUY",
			ButtonColor = Theme.Gold,
			Enabled = true,
			OnClick = function()
				self:fire("PromptProduct", product.Id)
			end,
		})
	end
end

-- Nastavení ------------------------------------------------------------------------------

function Panels:renderSettings()
	local settings = (self.Profile and self.Profile.Settings) or {}

	local entries = {
		{ Key = "Music", Icon = "🎵", Title = "Music", Detail = "Background music." },
		{ Key = "Sfx", Icon = "🔊", Title = "Sound effects", Detail = "Smashes, pickups and squeezes." },
		{ Key = "HideUi", Icon = "🙈", Title = "Hide interface", Detail = "Clean screen for screenshots and videos." },
		{ Key = "LowGraphics", Icon = "🪫", Title = "Low graphics", Detail = "Fewer particles and no squishy in hand. Helps on weaker phones." },
	}

	for index, entry in entries do
		local enabled = settings[entry.Key] == true

		self:row(index, {
			Color = if enabled then Theme.Acid else Theme.PanelDeep,
			Icon = entry.Icon,
			Title = entry.Title,
			Detail = entry.Detail,
			ButtonText = if enabled then "ON" else "OFF",
			ButtonColor = if enabled then Theme.Success else Theme.PanelDeep,
			Enabled = true,
			OnClick = function()
				self:fire("ToggleSetting", entry.Key)
			end,
		})
	end
end

-- Obchod ---------------------------------------------------------------------------

function Panels:renderTrade()
	local trade = self.Trade

	--[[
		Došlá žádost má přednost před vším ostatním: kdo ji přehlédne,
		nechá druhého čekat, dokud nevyprší.
	]]
	if self.Invite then
		self:row(1, {
			Color = Theme.Acid,
			Icon = "📨",
			Title = `{self.Invite.Name} wants to trade`,
			Detail = "Accept to open the trade window. Both of you have to confirm before anything moves.",
			ButtonText = "ACCEPT",
			ButtonColor = Theme.Success,
			Enabled = true,
			OnClick = function()
				self:fire("TradeRespond", "yes")
			end,
		})

		self:row(2, {
			Color = Theme.PanelDeep,
			Icon = "✖️",
			Title = "Not now",
			Detail = "Declines the request.",
			ButtonText = "DECLINE",
			ButtonColor = Theme.Danger,
			Enabled = true,
			OnClick = function()
				self:fire("TradeRespond", "no")
			end,
		})
		return
	end

	if not trade or not trade.Active then
		self:renderTradeCandidates()
		return
	end

	self:tradeHeader(1, trade)

	local order = 1

	for _, item in trade.Mine do
		order += 1
		self:tradeItem(order, item, true)
	end

	for _, item in trade.Theirs do
		order += 1
		self:tradeItem(order, item, false)
	end

	-- Vlastní hračky k přidání; nabídnuté už mezi nimi nejsou
	local offered = {}
	for _, item in trade.Mine do
		offered[item.Id] = item.Count
	end

	for _, item in self.Profile.Squishies or {} do
		local left = item.Count - (offered[item.Id] or 0)
		if left <= 0 then
			continue
		end

		order += 1
		self:row(order, {
			Color = item.Color,
			Preview = { Id = item.Id, Shape = item.Shape, Color = item.Color },
			Title = `{item.Name}  <font color="#2A1D46">×{left}</font>`,
			Detail = `{item.Grade}  ·  +{math.floor(item.Power * 100)}% power`,
			ButtonText = "ADD",
			ButtonColor = Theme.Cyan,
			Enabled = true,
			OnClick = function()
				self:fire("TradeAdd", item.Id)
			end,
		})
	end
end

function Panels:renderTradeCandidates()
	if #self.Candidates == 0 then
		self:row(1, {
			Color = Theme.PanelDeep,
			Icon = "👤",
			Title = "Nobody to trade with",
			Detail = "Trading works between players on the same server. Wait for someone to join.",
			ButtonText = "—",
			ButtonColor = Theme.PanelDeep,
			Enabled = false,
		})
		return
	end

	for index, candidate in self.Candidates do
		self:row(index, {
			Color = Theme.Cyan,
			Icon = "👤",
			Title = candidate.Name,
			Detail = "Sends a trade request. They have to accept before anything opens.",
			ButtonText = "TRADE",
			ButtonColor = Theme.Gems,
			Enabled = true,
			OnClick = function()
				self:fire("TradeRequest", tostring(candidate.UserId))
			end,
		})
	end
end

--[[
	Hlavička obchodu. Stav potvrzení musí být vidět u obou stran naráz —
	hráč musí poznat, že druhý ještě nepotvrdil, i když sám už ano.
]]
function Panels:tradeHeader(order: number, trade)
	local card = Widgets.panel({
		Name = "TradeHeader",
		Size = UDim2.new(1, -12, 0, 104),
		Position = UDim2.fromScale(0, 0),
		Color = Theme.Violet,
		Radius = Style.Radius.Card,
		Parent = self.Scroll,
	})
	card.LayoutOrder = order

	Widgets.label({
		Text = `Trading with <b>{trade.Partner}</b>`,
		Size = UDim2.new(1, -24, 0, 24),
		Position = UDim2.new(0, 12, 0, 8),
		TextSize = 20,
		Parent = card,
	})

	Widgets.label({
		Text = `You: {if trade.ConfirmedMine then "✅ confirmed" else "waiting"}   ·   `
			.. `{trade.Partner}: {if trade.ConfirmedTheirs then "✅ confirmed" else "waiting"}`
			.. `   ·   {Format.time(trade.SecondsLeft)}`,
		Size = UDim2.new(1, -24, 0, 20),
		Position = UDim2.new(0, 12, 0, 32),
		Color = Theme.TextDim,
		Font = Style.Font.Detail,
		TextSize = 14,
		Parent = card,
		Outline = 0,
	})

	local confirm = Widgets.button({
		Text = if trade.ConfirmedMine then "CONFIRMED" else "CONFIRM",
		Size = UDim2.new(0.5, -18, 0, 40),
		Position = UDim2.new(0, 12, 1, -48),
		Color = if trade.ConfirmedMine then Theme.PanelDeep else Theme.Success,
		TextSize = 17,
		Parent = card,
	})

	if trade.ConfirmedMine then
		confirm.Active = false
		confirm.TextTransparency = 0.3
	else
		confirm.MouseButton1Click:Connect(function()
			self:fire("TradeConfirm", "")
		end)
	end

	local cancel = Widgets.button({
		Text = "CANCEL",
		Size = UDim2.new(0.5, -18, 0, 40),
		Position = UDim2.new(0.5, 6, 1, -48),
		Color = Theme.Danger,
		TextSize = 17,
		Parent = card,
	})
	cancel.MouseButton1Click:Connect(function()
		self:fire("TradeCancel", "")
	end)
end

function Panels:tradeItem(order: number, item, mine: boolean)
	local color = item.Color or Theme.PanelDeep

	self:row(order, {
		Color = if mine then color else Style.darken(color, 0.25),
		Preview = { Id = item.Id, Shape = item.Shape, Color = color },
		Title = `{if mine then "YOU" else "THEM"}: {item.Name}  <font color="#2A1D46">×{item.Count}</font>`,
		Detail = `{item.Grade}  ·  +{math.floor(item.Power * 100)}% power`,
		ButtonText = if mine then "REMOVE" else "—",
		ButtonColor = if mine then Theme.Danger else Theme.PanelDeep,
		Enabled = mine,
		OnClick = function()
			self:fire("TradeRemove", item.Id)
		end,
	})
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
	elseif self.Kind == "style" then
		local kind = self.StyleKind or "trail"
		self.Title.Text = "~STYLE~"
		local parts = {}
		for _, name in Cosmetics.Kinds do
			local list = Cosmetics.list(name)
			table.insert(parts, `{Cosmetics.owned(self.Profile, name, self.Profile.Playtime)}/{#list} {name}s`)
		end
		self.Subtitle.Text = `{table.concat(parts, "  ·  ")}  ·  everything here is earned, nothing is sold`
		self:renderStyleSwitch(kind)
		self:renderCosmetics(kind)
	elseif self.Kind == "titles" then
		self.Title.Text = "~TITLES~"
		self.Subtitle.Text = `Walls smashed: {Format.full(self.Profile.Smashes)}`
		self:renderTitles()
	elseif self.Kind == "rebirth" then
		self.Title.Text = "~REBIRTH~"
		self.Subtitle.Text = `Reset your run for a permanent multiplier.  ·  {Perks.available(self.Profile)} perk token{if Perks.available(self.Profile) == 1 then "" else "s"} to spend`
		self:renderRebirth()
	elseif self.Kind == "squishies" then
		self.Title.Text = "~SQUISHIES~"
		self.Subtitle.Text = `{Format.multiplier(self.Profile.SquishMultiplier or 1)} from {#(self.Profile.Held or {})} in hand  ·  `
			.. "tap the one in your hand for free power"
		self:renderSquishies()
	elseif self.Kind == "daily" then
		self.Title.Text = "~DAILY~"
		self.Subtitle.Text = "Log in every day and finish quests to keep both streaks alive."
		self:renderDaily()
	elseif self.Kind == "codes" then
		self.Title.Text = "~CODES~"
		self.Subtitle.Text = "Codes give coins and gems. Each one works once per account."
		self:renderCodes()
	elseif self.Kind == "shop" then
		self.Title.Text = "~SHOP~"
		self.Subtitle.Text = "Nothing here blocks progress — it only speeds it up."
		self:renderShop()
	elseif self.Kind == "trade" then
		self.Title.Text = "~TRADE~"
		self.Subtitle.Text = "Both sides confirm before anything moves. Changing an offer clears both confirmations."
		self:renderTrade()
	elseif self.Kind == "settings" then
		self.Title.Text = "~SETTINGS~"
		self.Subtitle.Text = "Saved to your profile, so they follow you to every server."
		self:renderSettings()
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
	self.Root.Size = UDim2.new(0.86, 0, 0.82, 0)
	self:refresh()

	TweenService:Create(self.Root, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0.94, 0, 0.9, 0),
	}):Play()
end

function Panels:close()
	self.Root.Visible = false
	self.Shade.Visible = false
	self.Kind = nil
end

function Panels:setProfile(profile)
	self.Profile = profile

	--[[
		Rozdíl mezi serverovým a lokálním časem. Denní nabídka se odvozuje
		z čísla dne, takže hráč s posunutými hodinami by jinak viděl jinou
		slevu, než jakou mu server uzná — a klikal by na cenu, která
		neplatí.
	]]
	if profile and profile.ServerTime then
		self.TimeOffset = profile.ServerTime - os.time()
	end

	self:refresh()
end

function Panels:now(): number
	return os.time() + (self.TimeOffset or 0)
end

-- Denní odměny a úkoly chodí zvlášť, protože se mění jiným tempem než profil
function Panels:setRetention(retention)
	self.Retention = retention
	if self.Kind == "daily" then
		self:refresh()
	end
end

--[[
	Stav obchodu chodí zvlášť a mění se rychle. Překreslí se jen když je
	záložka obchodu otevřená — jinak by se přestavoval seznam, na který
	se nikdo nedívá.
]]
function Panels:setTrade(trade)
	self.Trade = trade
	if trade and trade.Active then
		self.Invite = nil
	end
	if self.Kind == "trade" then
		self:refresh()
	end
end

function Panels:setInvite(invite)
	self.Invite = invite
	if self.Kind == "trade" then
		self:refresh()
	end
end

function Panels:setCandidates(candidates)
	self.Candidates = candidates or {}
	if self.Kind == "trade" and not (self.Trade and self.Trade.Active) then
		self:refresh()
	end
end

function Panels:setOffers(offers)
	self.Offers = offers
	if self.Kind == "shop" then
		self:refresh()
	end
end

return Panels

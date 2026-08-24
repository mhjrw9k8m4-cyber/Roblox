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
local Live = require(Shared.Live)

local Style = require(script.Parent.Style)
local Widgets = require(script.Parent.Widgets)

local Theme = Config.Theme

local TABS = {
	{ Id = "upgrades", Icon = "⚡", Text = "Upgrades" },
	{ Id = "pets", Icon = "🥚", Text = "Pets" },
	{ Id = "daily", Icon = "📅", Text = "Daily" },
	{ Id = "worlds", Icon = "🌍", Text = "Worlds" },
	{ Id = "codes", Icon = "🎟️", Text = "Codes" },
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

-- Pety a vejce ---------------------------------------------------------------------

--[[
	Nahoře vejce ke koupi, pod nimi vlastnění pety. Kliknutí na peta ho
	nasadí nebo sundá — dvě tlačítka na jedné kartě by byla přeplácaná.
]]
function Panels:renderPets()
	local profile = self.Profile
	local order = 0

	for _, egg in Live.Eggs do
		order += 1
		local affordable = profile.Coins >= egg.Price

		self:row(order, {
			Color = egg.Color,
			Icon = "🥚",
			Title = egg.Name,
			Detail = self:eggOdds(egg.Id),
			ButtonText = `💰 {Format.short(egg.Price)}`,
			ButtonColor = if affordable then Theme.Gold else Theme.PanelDeep,
			Enabled = affordable,
			OnClick = function()
				self:fire("BuyEgg", egg.Id)
			end,
		})
	end

	local pets = profile.Pets or {}
	if #pets == 0 then
		order += 1
		self:row(order, {
			Color = Theme.PanelDeep,
			Icon = "❔",
			Title = "No pets yet",
			Detail = "Buy an egg above. Pets multiply your power and follow you around.",
			ButtonText = "—",
			ButtonColor = Theme.PanelDeep,
			Enabled = false,
		})
		return
	end

	local slots = profile.PetSlots or 3
	local equippedCount = #(profile.EquippedPets or {})

	for _, pet in pets do
		order += 1
		local rarity = Live.rarity(pet.Rarity)
		local full = equippedCount >= slots and not pet.Equipped

		self:row(order, {
			Color = rarity.Color,
			Icon = "🐾",
			Title = `{pet.Name}  <font color="#2A1D46">×{pet.Count}</font>`,
			Detail = `{rarity.Name}  ·  +{math.floor(pet.Power * 100)}% power`,
			Chips = { { Icon = "⚡", Text = `+{math.floor(pet.Power * 100)}%`, Color = Theme.PanelDeep } },
			ButtonText = if pet.Equipped then "UNEQUIP" elseif full then `{equippedCount}/{slots} FULL` else "EQUIP",
			ButtonColor = if pet.Equipped then Theme.Success elseif full then Theme.PanelDeep else Theme.Cyan,
			Enabled = pet.Equipped or not full,
			OnClick = function()
				self:fire("EquipPet", pet.Id)
			end,
		})
	end
end

-- Text se šancemi z vejce, aby hráč věděl, do čeho jde
function Panels:eggOdds(eggId: string): string
	local pool = Live.eggPool(eggId)
	local total = 0
	local byRarity: { [string]: number } = {}

	for _, pet in pool do
		local weight = Live.rarity(pet.Rarity).Weight
		byRarity[pet.Rarity] = (byRarity[pet.Rarity] or 0) + weight
		total += weight
	end

	local parts = {}
	for _, name in { "Common", "Rare", "Epic", "Legendary", "Mythic" } do
		local weight = byRarity[name]
		if weight then
			table.insert(parts, `{name} {string.format("%.1f", weight / total * 100)}%`)
		end
	end

	return table.concat(parts, "  ·  ")
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
			Text = if entry.Egg then `💎{entry.Gems}\n🥚` else `💎{entry.Gems}`,
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

	if not offers or (#offers.Passes == 0 and #offers.Products == 0) then
		self:row(1, {
			Color = Theme.PanelDeep,
			Icon = "🛠️",
			Title = "Shop not set up yet",
			Detail = "Add gamepass and product IDs in src/shared/Live.luau. Until then nothing is shown here, so players never see a button that does nothing.",
			ButtonText = "—",
			ButtonColor = Theme.PanelDeep,
			Enabled = false,
		})
		return
	end

	local order = 0

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
		{ Key = "Sfx", Icon = "🔊", Title = "Sound effects", Detail = "Smashes, pickups and pets." },
		{ Key = "HideUi", Icon = "🙈", Title = "Hide interface", Detail = "Clean screen for screenshots and videos." },
		{ Key = "LowGraphics", Icon = "🪫", Title = "Low graphics", Detail = "Fewer particles and no pets on screen. Helps on weaker phones." },
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
	elseif self.Kind == "pets" then
		self.Title.Text = "~PETS~"
		self.Subtitle.Text = `Pets multiply your power. {Format.multiplier(self.Profile.PetMultiplier or 1)} from {#(self.Profile.EquippedPets or {})} equipped.`
		self:renderPets()
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

-- Denní odměny a úkoly chodí zvlášť, protože se mění jiným tempem než profil
function Panels:setRetention(retention)
	self.Retention = retention
	if self.Kind == "daily" then
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

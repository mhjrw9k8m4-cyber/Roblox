--!strict
--[[
	HUD — rozvržení odkoukané z největších her v žánru.

	  vlevo nahoře    peníze a gemy jako chip pilulky se zeleným "+"
	  vlevo           mřížka ikon 2×N s popiskovou lištou pod ikonou
	  vpravo          promo sloupec s nabídkami za gemy
	  uprostřed       OBŘÍ číslo Poweru a pod ním rozpis násobičů v barvách
	  dole            tan/zlatá lišta postupu se stavem zdi
	  úplně dole      rychlé nákupy tří klíčových vylepšení

	Rozpis násobičů není dekorace: v žánru je to hlavní důvod, proč si
	hráč něco kupuje. Musí být vidět, odkud každý násobek přišel.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Combo = require(Shared.Combo)
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Live = require(Shared.Live)
local Zones = require(Shared.Zones)

local Layout = require(script.Parent.Layout)
local Style = require(script.Parent.Style)
local Widgets = require(script.Parent.Widgets)

local Theme = Config.Theme

local HUD = {}
HUD.__index = HUD

export type Handle = typeof(setmetatable({} :: any, HUD))

-- Levé menu: pořadí odpovídá tomu, jak často se to používá
local MENU = {
	{ Id = "chest", Icon = "🎁", Text = "FREE", Color = Theme.Gold },
	{ Id = "daily", Icon = "📅", Text = "DAILY", Color = Theme.Violet },
	{ Id = "squishies", Icon = "🧸", Text = "SQUISHIES", Color = Theme.Pink },
	{ Id = "upgrades", Icon = "⚡", Text = "UPGRADES", Color = Theme.Acid },
	{ Id = "worlds", Icon = "🌍", Text = "WORLDS", Color = Theme.Cyan },
	{ Id = "codes", Icon = "🎟️", Text = "CODES", Color = Theme.Spicy },
	{ Id = "trade", Icon = "🔄", Text = "TRADE", Color = Theme.Gems },
	{ Id = "rebirth", Icon = "⭐", Text = "REBIRTH", Color = Theme.Danger },
	{ Id = "settings", Icon = "⚙️", Text = "SETTINGS", Color = Theme.PanelDeep },
}

-- Rychlé nákupy ve spodní řadě
local QUICK = {
	{ Id = "Power", Icon = "💪", Color = Theme.Pink },
	{ Id = "Magnet", Icon = "🧲", Color = Theme.Violet },
	{ Id = "Speed", Icon = "⚡", Color = Theme.Gold },
}

function HUD.new(screen: ScreenGui): Handle
	local self = setmetatable({}, HUD)

	self.Screen = screen

	--[[
		Všechno HUD leží v jednom kontejneru, ne přímo na ScreenGui.
		Škálování pro malé obrazovky se pak dá udělat jedním `UIScale`
		místo přepočítávání každého prvku zvlášť.
	]]
	local container = Instance.new("Frame")
	container.Name = "Hud"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.Parent = screen
	self.Container = container

	self.OnAction = nil :: ((string) -> ())?
	self.OnBuyBoost = nil :: ((string) -> ())?
	self.OnQuickBuy = nil :: ((string) -> ())?
	self.Profile = nil
	self.MenuButtons = {} :: { [string]: TextButton }
	self.BoostCards = {} :: { [string]: { Button: TextButton, Subtitle: TextLabel } }
	self.QuickButtons = {} :: { [string]: { Button: TextButton, Price: TextLabel } }
	self.Badges = {} :: { [string]: Frame }
	-- Kořeny všech skupin, aby šlo UI schovat jedním přepínačem
	self.Roots = {} :: { Frame }

	self:buildWallet()
	self:buildHappy()
	self:buildMenu()
	self:buildPromos()
	self:buildCenter()
	self:buildCombo()
	self:buildSurge()
	self:buildBottom()

	Layout.onChange(function(layout)
		self:applyLayout(layout)
	end)

	return self
end

--[[
	Reakce na velikost obrazovky.

	Na úzké obrazovce se rozvržení nemění velikostí, ale tvarem: mřížka
	ikon se složí do jednoho sloupce a promo karty se zmenší. Zmenšit
	dvousloupcovou mřížku na polovinu by nepomohlo — na tlačítko by pak
	nešlo kliknout prstem.
]]
function HUD:applyLayout(layout)
	--[[
		Škáluje se každá skupina zvlášť, ne kontejner.

		`UIScale` zmenšuje prvek kolem jeho vlastního AnchorPointu. Na
		celoobrazovkovém kontejneru (anchor 0,0) by se všechno stáhlo
		k levému hornímu rohu a prvky ukotvené vpravo by skončily
		uprostřed obrazovky. Skupiny mají anchor ve svém rohu, takže
		zmenšení je drží tam, kde mají být.
	]]
	for _, root in self.Roots do
		Layout.applyScale(root)
	end

	local grid = self.MenuGrid
	if grid then
		local columns = if layout.Narrow then 1 else 2
		local cell = grid.CellSize.X.Offset
		local padding = grid.CellPadding.X.Offset
		;(self.MenuColumn :: Frame).Size =
			UDim2.new(0, columns * cell + (columns - 1) * padding, 0, 520)
	end

	local promos = self.PromoColumn
	if promos then
		local width = if layout.Narrow then 150 else 206
		local height = if layout.Narrow then 46 else 58
		promos.Size = UDim2.new(0, width, 0, 260)

		for _, child in promos:GetChildren() do
			if child:IsA("TextButton") then
				child.Size = UDim2.new(1, 0, 0, height)
			end
		end
	end
end

-- Peníze a gemy ---------------------------------------------------------------------

function HUD:buildWallet()
	local holder = Instance.new("Frame")
	holder.Name = "Wallet"
	holder.Size = UDim2.new(0, 250, 0, 142)
	holder.Position = UDim2.new(0, 14, 0, 12)
	holder.BackgroundTransparency = 1
	holder.Parent = self.Container
	table.insert(self.Roots, holder)

	local layout = Widgets.list(holder, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left

	-- Zelené "+" vedle peněz je v žánru zavedená zkratka do obchodu
	local coinRow = Instance.new("Frame")
	coinRow.Size = UDim2.new(1, 0, 0, 44)
	coinRow.BackgroundTransparency = 1
	coinRow.LayoutOrder = 1
	coinRow.Parent = holder

	local plus = Widgets.button({
		Text = "+",
		Size = UDim2.fromOffset(42, 42),
		Color = Theme.Success,
		TextSize = 30,
		Radius = Style.Radius.Chip,
		Parent = coinRow,
	})
	plus.MouseButton1Click:Connect(function()
		if self.OnAction then
			self.OnAction("upgrades")
		end
	end)

	local _, coins = Widgets.chip({
		Icon = "💰",
		Text = "0",
		Color = Theme.PanelDeep,
		Size = UDim2.new(1, -50, 1, 0),
		Position = UDim2.fromOffset(50, 0),
		Parent = coinRow,
		TextSize = 22,
	})
	coins.TextColor3 = Theme.Coins
	self.CoinsLabel = coins

	local _, gems = Widgets.chip({
		Icon = "💎",
		Text = "0",
		Color = Theme.PanelDeep,
		Size = UDim2.new(0, 160, 0, 42),
		Parent = holder,
		TextSize = 22,
	})
	gems.TextColor3 = Theme.Gems
	;(gems.Parent :: Frame).LayoutOrder = 2
	self.GemsLabel = gems

	--[[
		Trofej s celkovým počtem průrazů.

		Peníze a gemy se utrácejí, takže po nákupu spadnou k nule —
		hráč z nich nepozná, jak daleko došel. Průrazy jsou jediné číslo,
		které jen roste, a ve velkých hrách žánru visí vedle peněz právě
		proto: je to ta věc, na kterou je hráč hrdý.
	]]
	local _, smashes = Widgets.chip({
		Icon = "🏆",
		Text = "0",
		Color = Theme.PanelDeep,
		Size = UDim2.new(0, 190, 0, 42),
		Parent = holder,
		TextSize = 22,
	})
	smashes.TextColor3 = Theme.Gold
	;(smashes.Parent :: Frame).LayoutOrder = 3
	self.SmashesLabel = smashes
end

-- Levá mřížka ikon --------------------------------------------------------------------

function HUD:buildMenu()
	local column = Instance.new("Frame")
	column.Name = "Menu"
	column.Size = UDim2.new(0, 190, 0, 510)
	column.Position = UDim2.new(0, 14, 0, 116)
	column.BackgroundTransparency = 1
	column.Parent = self.Container
	table.insert(self.Roots, column)

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(88, 88)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = column

	self.MenuColumn = column
	self.MenuGrid = grid

	for index, entry in MENU do
		local tile = Widgets.tile({
			Icon = entry.Icon,
			Text = entry.Text,
			Color = entry.Color,
			Size = UDim2.fromOffset(88, 88),
			Parent = column,
			LayoutOrder = index,
			IconInset = if entry.Id == "chest" then 20 else 0,
		})

		tile.MouseButton1Click:Connect(function()
			if self.OnAction then
				self.OnAction(entry.Id)
			end
		end)

		-- Červený odznak upozorňuje, že tam něco čeká k vyzvednutí
		local badge = Instance.new("Frame")
		badge.Name = "Badge"
		badge.Size = UDim2.fromOffset(16, 16)
		badge.Position = UDim2.new(1, -6, 0, 4)
		badge.AnchorPoint = Vector2.new(1, 0)
		badge.BackgroundColor3 = Theme.Danger
		badge.BorderSizePixel = 0
		badge.Visible = false
		badge.Parent = tile
		Style.corner(badge, 8)
		Style.stroke(badge, Theme.Ink, 2)

		self.Badges[entry.Id] = badge
		self.MenuButtons[entry.Id] = tile
	end

	-- Odpočet truhly má vlastní pruh nahoře; popisek "FREE" musí zůstat
	local chest = self.MenuButtons.chest
	local timerStrip = Instance.new("Frame")
	timerStrip.Name = "Timer"
	timerStrip.Size = UDim2.new(1, -10, 0, 18)
	timerStrip.Position = UDim2.new(0, 5, 0, 4)
	timerStrip.BackgroundColor3 = Style.darken(Theme.Gold, 0.5)
	timerStrip.BorderSizePixel = 0
	timerStrip.Parent = chest
	Style.corner(timerStrip, 6)

	self.ChestTimer = Widgets.label({
		Text = "",
		Size = UDim2.new(1, -4, 1, 0),
		Position = UDim2.fromOffset(2, 0),
		Align = Enum.TextXAlignment.Center,
		TextSize = 13,
		Parent = timerStrip,
		Outline = 2,
	})
end

-- Pravý promo sloupec --------------------------------------------------------------------

function HUD:buildPromos()
	local column = Instance.new("Frame")
	column.Name = "Promos"
	column.Size = UDim2.new(0, 224, 0, 330)
	column.Position = UDim2.new(1, -14, 0, 16)
	column.AnchorPoint = Vector2.new(1, 0)
	column.BackgroundTransparency = 1
	column.Parent = self.Container
	table.insert(self.Roots, column)
	Widgets.list(column, 9)
	self.PromoColumn = column

	local shop = Widgets.promo({
		Title = "SHOP",
		Subtitle = "UPGRADES",
		Icon = "💎",
		ColorA = Theme.Danger,
		ColorB = Theme.Pink,
		Size = UDim2.new(1, 0, 0, 74),
		Parent = column,
		LayoutOrder = 1,
	})
	shop.MouseButton1Click:Connect(function()
		if self.OnAction then
			self.OnAction("upgrades")
		end
	end)

	for index, boost in Config.Boosts do
		local card, subtitle = Widgets.promo({
			Title = string.upper(boost.Name),
			Subtitle = `ONLY 💎{boost.Gems}`,
			Icon = boost.Icon,
			ColorA = Theme.Violet,
			ColorB = Theme.Cyan,
			Size = UDim2.new(1, 0, 0, 74),
			Parent = column,
			LayoutOrder = index + 1,
		})

		card.MouseButton1Click:Connect(function()
			if self.OnBuyBoost then
				self.OnBuyBoost(boost.Id)
			end
		end)

		self.BoostCards[boost.Id] = { Button = card, Subtitle = subtitle }
	end
end

-- Střed: obří číslo a rozpis násobičů ---------------------------------------------------------

function HUD:buildCenter()
	local holder = Instance.new("Frame")
	holder.Name = "Center"
	-- Relativní šířka se stropem: na telefonu se vejde, na monitoru
	-- se neroztáhne přes celou obrazovku.
	holder.Size = UDim2.new(0.62, 0, 0, 190)
	holder.Position = UDim2.new(0.5, 0, 1, -168)
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.BackgroundTransparency = 1
	holder.Parent = self.Container
	table.insert(self.Roots, holder)

	Layout.constrain(holder, Vector2.new(560, 190), Vector2.new(300, 190))

	self.PowerLabel = Widgets.bigNumber({
		Text = "0 POWER",
		Size = UDim2.new(1, 0, 0, 74),
		Position = UDim2.new(0, 0, 0, 108),
		Color = Theme.Power,
		Parent = holder,
	})

	--[[
		Rozpis násobičů ve dvou sloupcích po stranách velkého čísla, ne
		pod ním.

		V referencích žánru to tak je z dobrého důvodu: uprostřed obrazovky
		má být to jediné číslo, na které hráč kouká pořád. Rozpis patří po
		stranách, kde se dá přečíst, když ho člověk hledá, a nepřekáží,
		když ne. Sloupce jsou navíc mimo dráhu běhu, takže nezakrývají zeď.
	]]
	local function column(alignRight: boolean): Frame
		local frame = Instance.new("Frame")
		frame.Name = if alignRight then "MultipliersRight" else "MultipliersLeft"
		frame.Size = UDim2.new(0, 300, 0, 100)
		frame.Position = if alignRight
			then UDim2.new(1, 16, 0, 4)
			else UDim2.new(0, -316, 0, 4)
		frame.BackgroundTransparency = 1
		frame.Parent = holder

		local layout = Widgets.list(frame, 1)
		layout.HorizontalAlignment = if alignRight
			then Enum.HorizontalAlignment.Left
			else Enum.HorizontalAlignment.Right
		return frame
	end

	local left = column(false)
	local right = column(true)

	local function line(color: Color3, order: number, alignRight: boolean): TextLabel
		local label = Widgets.label({
			Text = "",
			Size = UDim2.new(1, 0, 0, 22),
			Align = if alignRight then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right,
			Color = color,
			TextSize = 18,
			Parent = if alignRight then right else left,
			Outline = 3,
		})
		label.LayoutOrder = order
		return label
	end

	--[[
		Vlevo to, co si hráč koupil; vpravo to, co si vysloužil.
		Rozdělení není kosmetické — hráč tak ví, kterou stranu má
		zvětšovat penězi a kterou hraním.
	]]
	self.MultiplierLines = {
		Upgrade = line(Theme.Acid, 1, false),
		Boost = line(Theme.Pink, 2, false),
		World = line(Theme.Gold, 3, false),

		Rebirth = line(Theme.Cyan, 1, true),
		-- Kolo je jediné číslo, které mění obtížnost zdí, a hráč ho
		-- jinak nemá kde vidět — jen si všimne, že zdi ztěžkly.
		Lap = line(Theme.Violet, 2, true),
		-- Jméno zóny; barvu si nastavuje samo podle toho, kde hráč je
		Zone = line(Theme.Text, 3, true),
	}
end

-- Combo ---------------------------------------------------------------------------------------

--[[
	Ukazatel řetězu. Schválně je vidět jen když řetěz běží — prázdný
	rámeček by na obrazovce jen zabíral místo a nic neříkal.

	Lišta ubývá plynule na klientovi, ale číslo přichází ze serveru.
	Klient tak nikdy netvrdí vyšší násobič, než jaký se opravdu počítá.
]]
function HUD:buildCombo()
	local holder = Instance.new("Frame")
	holder.Name = "Combo"
	holder.Size = UDim2.new(0, 206, 0, 116)
	holder.Position = UDim2.new(1, -14, 0, 296)
	holder.AnchorPoint = Vector2.new(1, 0)
	holder.BackgroundTransparency = 1
	holder.Visible = false
	holder.Parent = self.Container
	table.insert(self.Roots, holder)

	local card = Widgets.panel({
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
		Color = Theme.Panel,
		Radius = Style.Radius.Card,
		Parent = holder,
	})

	self.ComboTier = Widgets.label({
		Text = "",
		Size = UDim2.new(1, -16, 0, 20),
		Position = UDim2.fromOffset(8, 6),
		Align = Enum.TextXAlignment.Center,
		Color = Theme.Cyan,
		TextSize = 16,
		Parent = card,
	})

	self.ComboCount = Widgets.bigNumber({
		Text = "0x",
		Size = UDim2.new(1, -16, 0, 46),
		Position = UDim2.fromOffset(8, 26),
		Color = Theme.Gold,
		Parent = card,
	})

	self.ComboGain = Widgets.label({
		Text = "",
		Size = UDim2.new(1, -16, 0, 18),
		Position = UDim2.fromOffset(8, 72),
		Align = Enum.TextXAlignment.Center,
		Color = Theme.TextDim,
		Font = Style.Font.Detail,
		TextSize = 14,
		Parent = card,
	})

	local _, fill = Widgets.bar({
		Size = UDim2.new(1, -16, 0, 8),
		Position = UDim2.fromOffset(8, 96),
		Color = Theme.Cyan,
		Parent = card,
	})

	self.ComboHolder = holder
	self.ComboCard = card
	self.ComboFill = fill
	self.ComboChain = 0
	self.ComboTierIndex = 1
	self.ComboUntil = 0
	-- Délku okna posílá server (perk ji prodlužuje); do první zprávy platí základ
	self.ComboWindow = Combo.Window
end

--[[
	Nový stav řetězu ze serveru. Vrací index stupně, aby si volající
	mohl na změnu stupně pověsit zvuk a kameru, aniž by si to počítal
	podruhé sám.
]]
function HUD:setCombo(chain: number, now: number, window: number?): number
	local holder = self.ComboHolder
	if not holder then
		return 1
	end

	self.ComboWindow = window or self.ComboWindow or Combo.Window
	self.ComboChain = chain
	self.ComboUntil = now + self.ComboWindow

	if chain <= 0 then
		holder.Visible = false
		self.ComboTierIndex = 1
		return 1
	end

	local tier = Combo.tier(chain)
	local index = Combo.tierIndex(chain)

	holder.Visible = true
	self.ComboCount.Text = `{chain}x`
	self.ComboTier.Text = tier.Name
	self.ComboTier.TextColor3 = tier.Color
	self.ComboGain.Text = `{Format.multiplier(Combo.multiplier(chain))} per pickup`
	Widgets.setColor(self.ComboCard :: any, tier.Color)
	self.ComboFill.BackgroundColor3 = tier.Color

	-- Ťuknutí jen při přeskočení stupně, ne u každého pickupu —
	-- padesátkrát za vteřinu poskakující karta je nečitelná.
	if index ~= self.ComboTierIndex then
		Widgets.pop(self.ComboCount, 1.25)
		self.ComboTierIndex = index
	end

	return index
end

--[[
	Plynulé ubývání lišty. Volá se každý snímek, ne jen při pickupu.

	Vrací `true` v tom jediném snímku, kdy řetěz spadl — volající podle
	toho sundá efekty. Kdyby to hlásil server, přišla by zpráva až s dalším
	pickupem, tedy nikdy: řetěz padá právě tím, že hráč přestal sbírat.
]]
function HUD:tickCombo(now: number): boolean
	local holder = self.ComboHolder
	if not holder or not holder.Visible then
		return false
	end

	local left = self.ComboUntil - now
	if left <= 0 then
		holder.Visible = false
		self.ComboChain = 0
		self.ComboTierIndex = 1
		self.ComboFill.Size = UDim2.fromScale(0, 1)
		return true
	end

	self.ComboFill.Size = UDim2.fromScale(left / math.max(self.ComboWindow, 0.01), 1)
	return false
end

-- Nálet -----------------------------------------------------------------------------------------

--[[
	Ukazatel náletu. Sedí pod kartou comba a je vidět jen když nálet běží.

	Schválně stejný tvar jako combo: obojí je dočasné zrychlení, které
	za pár vteřin skončí, a hráč tak nemusí učit dva různé prvky.
]]
function HUD:buildSurge()
	local holder = Instance.new("Frame")
	holder.Name = "Surge"
	holder.Size = UDim2.new(0, 206, 0, 52)
	holder.Position = UDim2.new(1, -14, 0, 420)
	holder.AnchorPoint = Vector2.new(1, 0)
	holder.BackgroundTransparency = 1
	holder.Visible = false
	holder.Parent = self.Container
	table.insert(self.Roots, holder)

	local card = Widgets.panel({
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
		Color = Theme.Acid,
		Radius = Style.Radius.Card,
		Parent = holder,
	})

	Widgets.label({
		Text = "⚡ SURGE",
		Size = UDim2.new(1, -16, 0, 22),
		Position = UDim2.fromOffset(8, 6),
		Align = Enum.TextXAlignment.Center,
		Color = Style.contrast(Theme.Acid),
		TextSize = 18,
		Parent = card,
	})

	local _, fill = Widgets.bar({
		Size = UDim2.new(1, -16, 0, 10),
		Position = UDim2.fromOffset(8, 32),
		Color = Style.contrast(Theme.Acid),
		Parent = card,
	})

	self.SurgeHolder = holder
	self.SurgeFill = fill
	self.SurgeUntil = 0
	self.SurgeLength = 1
end

--[[
	`endsAt` je absolutní serverový čas konce, ne délka.

	Kdyby si HUD konec dopočítával sám, musel by znát aktuální serverový
	čas — a ten má v profilu jen jako snímek z poslední zprávy, takže by
	se lišta rozešla s tím, co doopravdy platí.
]]
function HUD:setSurge(endsAt: number, length: number)
	if not self.SurgeHolder then
		return
	end

	self.SurgeLength = math.max(length, 0.01)
	self.SurgeUntil = endsAt
	self.SurgeHolder.Visible = true
	Widgets.pop(self.SurgeHolder, 1.12)
end

-- Volá se každý snímek; `now` je serverový čas, ne lokální.
function HUD:tickSurge(now: number)
	local holder = self.SurgeHolder
	if not holder or not holder.Visible then
		return
	end

	local left = self.SurgeUntil - now
	if left <= 0 then
		holder.Visible = false
		return
	end

	self.SurgeFill.Size = UDim2.fromScale(left / self.SurgeLength, 1)
end

-- Spodek: lišta postupu a rychlé nákupy ---------------------------------------------------------

function HUD:buildBottom()
	local holder = Instance.new("Frame")
	holder.Name = "Bottom"
	holder.Size = UDim2.new(0.74, 0, 0, 128)
	holder.Position = UDim2.new(0.5, 0, 1, -12)
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.BackgroundTransparency = 1
	holder.Parent = self.Container
	table.insert(self.Roots, holder)

	Layout.constrain(holder, Vector2.new(720, 128), Vector2.new(340, 128))

	-- Tečky za jednotlivé zdi světa
	local dots = Instance.new("Frame")
	dots.Name = "Dots"
	dots.Size = UDim2.new(1, 0, 0, 14)
	dots.BackgroundTransparency = 1
	dots.Parent = holder
	Widgets.list(dots, 5, Enum.FillDirection.Horizontal)

	self.Dots = {}
	for index = 1, Config.Track.BarrierCount do
		local dot = Instance.new("Frame")
		dot.Size = UDim2.fromOffset(14, 14)
		dot.BackgroundColor3 = Theme.PanelDeep
		dot.BorderSizePixel = 0
		dot.LayoutOrder = index
		dot.Parent = dots
		Style.corner(dot, 7)
		Style.stroke(dot, Theme.Ink, 2)
		self.Dots[index] = dot
	end

	local _, fill = Widgets.bar({
		Size = UDim2.new(1, 0, 0, 46),
		Position = UDim2.new(0, 0, 0, 22),
		Parent = holder,
	})
	self.ProgressFill = fill

	self.WallLabel = Widgets.label({
		Text = "",
		Size = UDim2.new(0.5, -20, 0, 46),
		Position = UDim2.new(0, 16, 0, 22),
		TextSize = 24,
		Parent = holder,
	})

	self.ProgressLabel = Widgets.label({
		Text = "",
		Size = UDim2.new(0.5, -20, 0, 46),
		Position = UDim2.new(0.5, 4, 0, 22),
		Align = Enum.TextXAlignment.Right,
		TextSize = 24,
		Parent = holder,
	})

	-- Rychlé nákupy: to samé, co dělají "+20Qa Speed" tlačítka v referenci
	local quick = Instance.new("Frame")
	quick.Name = "Quick"
	quick.Size = UDim2.new(1, 0, 0, 50)
	quick.Position = UDim2.new(0, 0, 0, 76)
	quick.BackgroundTransparency = 1
	quick.Parent = holder
	Widgets.list(quick, 8, Enum.FillDirection.Horizontal)

	for index, entry in QUICK do
		local upgrade = Config.upgrade(entry.Id)
		local button = Widgets.button({
			Text = "",
			-- Třetina šířky minus mezery, ať se vejdou vždycky tři vedle sebe
			Size = UDim2.new(1 / #QUICK, -6, 1, 0),
			Color = entry.Color,
			Parent = quick,
		})
		button.LayoutOrder = index

		Widgets.label({
			Text = `{entry.Icon} {upgrade.Name}`,
			Size = UDim2.new(1, -16, 0, 22),
			Position = UDim2.new(0, 8, 0, 4),
			Align = Enum.TextXAlignment.Center,
			TextSize = 18,
			Parent = button,
		})

		local price = Widgets.label({
			Text = "",
			Size = UDim2.new(1, -16, 0, 20),
			Position = UDim2.new(0, 8, 0, 25),
			Align = Enum.TextXAlignment.Center,
			TextSize = 17,
			Parent = button,
		})

		button.MouseButton1Click:Connect(function()
			if self.OnQuickBuy then
				self.OnQuickBuy(entry.Id)
			end
		end)

		self.QuickButtons[entry.Id] = { Button = button, Price = price }
	end
end

--[[
	Pruh "x2 COINS" nad peněženkou.

	Je to jediná věc na obrazovce, která se objeví sama od sebe — proto
	musí být nepřehlédnutelná a proto zase zmizí. Trvale viditelný pruh
	s "x1" by byl jen další řádek, kterého si nikdo nevšimne.
]]
function HUD:buildHappy()
	local card = Widgets.panel({
		Name = "Happy",
		Size = UDim2.new(0, 210, 0, 40),
		Position = UDim2.new(0, 14, 0, 158),
		Color = Theme.Gold,
		Parent = self.Container,
	})
	card.Visible = false
	table.insert(self.Roots, card)

	local label = Widgets.label({
		Text = "",
		Size = UDim2.new(1, -16, 1, 0),
		Position = UDim2.fromOffset(8, 0),
		Align = Enum.TextXAlignment.Center,
		Color = Theme.Ink,
		TextSize = 20,
		Parent = card,
	})
	label.Font = Style.Font.Display

	self.HappyCard = card
	self.HappyLabel = label
end

--[[
	Odpočet do konce okna. Volá se z tikání HUD, ne z profilu: okno běží
	na čase serveru a profil chodí jen občas, takže by pruh zamrzl na
	posledním čísle a zůstal viset i po konci.
]]
function HUD:refreshHappy(now: number)
	local card = self.HappyCard
	if not card then
		return
	end

	local left = Economy.happyRemaining(now)
	card.Visible = left > 0

	if left > 0 then
		self.HappyLabel.Text = `×{Live.Happy.Coins} COINS  {Format.time(left)}`
	end
end

-- Aktualizace -----------------------------------------------------------------------------------

function HUD:setProfile(profile)
	self.Profile = profile

	self.CoinsLabel.Text = Format.short(profile.Coins)
	self.GemsLabel.Text = Format.short(profile.Gems)
	self.SmashesLabel.Text = Format.short(profile.Smashes or 0)

	local world = Config.Worlds[profile.WorldIndex]
	local wall = math.min(profile.Barrier, Config.Track.BarrierCount)
	if world then
		--[[
			Vlevo na liště je terén, na kterém hráč právě stojí, ne jméno
			světa — to už drží pravý sloupec násobičů. Lišta tak popisuje
			místo pod nohama, což je přesně to, co se během běhu mění.
		]]
		local zone = Zones.at(math.clamp(wall, 1, Config.Track.BarrierCount))
		self.WallLabel.Text = `{string.upper(zone.Name)}  ·  WALL {wall}/{Config.Track.BarrierCount}`
		self.WallLabel.TextColor3 = zone.Edge
	end

	--[[
		Tečky: hotové zelené, ta právě běžící zlatá, zbytek tmavý.
		Bez zvýraznění té aktuální se v řadě dvanácti stejných teček
		nedá poznat, kde hráč je.
	]]
	for index, dot in self.Dots do
		if index < profile.Barrier then
			dot.BackgroundColor3 = Theme.Acid
		elseif index == profile.Barrier then
			dot.BackgroundColor3 = Theme.Gold
		else
			dot.BackgroundColor3 = Theme.PanelDeep
		end
	end

	self:refreshMultipliers()
	self:refreshQuickBuys()
	self:setPower(profile.Power)
	self:refreshTimers(profile.ServerTime or os.time())
end

--[[
	Rozpis násobičů. Zdroj, který nic nedělá (žádný rebirth, žádný boost),
	se schová — prázdný řádek "x1" je jen šum.
]]
function HUD:refreshMultipliers()
	local profile = self.Profile
	if not profile then
		return
	end

	local now = profile.ServerTime or os.time()
	local upgrade = Config.upgrade("Power")
	local upgradeLevel = (profile.Upgrades and profile.Upgrades.Power) or 0
	local world = Config.Worlds[profile.WorldIndex]

	local lines = self.MultiplierLines

	lines.Upgrade.Text = `+{math.floor(upgradeLevel * upgrade.PerLevel * 100)}% Power (Upgrades)`
	lines.Upgrade.Visible = upgradeLevel > 0

	lines.Rebirth.Text = `Multiplier {Format.multiplier(profile.RebirthMultiplier or 1)} (Rebirth)`
	lines.Rebirth.Visible = profile.Rebirths > 0

	local boost = Economy.boostMultiplier(profile, "Power", now)
	lines.Boost.Text = `Multiplier {Format.multiplier(boost)} (Boost)`
	lines.Boost.Visible = boost > 1

	lines.World.Text = if world then `Pickup +{Format.short(world.Pickup)} ({world.Name})` else ""
	lines.World.Visible = world ~= nil

	local lap = Economy.lap(profile)
	lines.Lap.Text = `Lap {lap + 1} — walls {Format.multiplier(Config.Track.LapPower ^ math.min(lap, Config.Track.LapCap))} tougher`
	lines.Lap.Visible = lap > 0

	--[[
		Jméno zóny, ve které hráč zrovna běží. Terén se pod ním mění, ale
		bez popisku by to bylo jen "jinak barevná podlaha" — takhle je
		z toho místo, které má jméno a kterého se dá dosáhnout.
	]]
	local barrier = math.clamp(profile.Barrier, 1, Config.Track.BarrierCount)
	local zone = Zones.at(barrier)
	local zoneIndex = Zones.indexAt(barrier)

	lines.Zone.Text = `{string.upper(zone.Name)}  ·  zone {zoneIndex}/{#Zones.List}`
	lines.Zone.TextColor3 = zone.Edge
end

function HUD:refreshQuickBuys()
	local profile = self.Profile
	if not profile then
		return
	end

	for id, entry in self.QuickButtons do
		local level = (profile.Upgrades and profile.Upgrades[id]) or 0
		local price = Config.upgradePrice(id, level)

		if not price then
			entry.Price.Text = "MAX"
			entry.Price.TextColor3 = Theme.Success
		else
			entry.Price.Text = `💰 {Format.short(price)}`
			entry.Price.TextColor3 = if profile.Coins >= price then Theme.Text else Theme.TextDim
		end
	end
end

function HUD:setPower(power: number)
	self.PowerLabel.Text = `{Format.short(power)} POWER`

	local profile = self.Profile
	if not profile then
		return
	end

	-- Sdílený výpočet, ne opsaný: stejné číslo drží i cedule na zdi
	local ratio, current, needed = Economy.barrierProgress(profile, power)

	Widgets.setProgress(self.ProgressFill, ratio)

	if current >= needed then
		self.ProgressFill.BackgroundColor3 = Theme.Acid
		self.ProgressLabel.Text = "SMASH IT!"
		self.ProgressLabel.TextColor3 = Theme.Acid
	else
		self.ProgressFill.BackgroundColor3 = Theme.BarFill
		self.ProgressLabel.Text = `{Format.short(current)} / {Format.short(needed)}`
		self.ProgressLabel.TextColor3 = Theme.Text
	end
end

--[[
	Skrytí UI pro screenshoty a videa. Velké číslo Poweru zůstává —
	bez něj by záběr ztratil to jediné, co ukazuje postup.
]]
function HUD:setHidden(hidden: boolean)
	for _, root in self.Roots do
		root.Visible = not hidden
	end

	-- Lišta události má vlastní viditelnost; zobrazit ji, když žádná
	-- událost neběží, by ukázalo prázdný odpočet.
	if self.EventHolder then
		self.EventHolder.Visible = not hidden and self.EventActive == true
	end

	if hidden then
		-- střed (obří číslo) necháváme viditelný
		local center = self.PowerLabel.Parent
		if center and center:IsA("Frame") then
			center.Visible = true
		end
	end
end

-- Odznaky u dlaždic: co je připravené k vyzvednutí
function HUD:setBadges(state: { [string]: boolean })
	for id, badge in self.Badges do
		badge.Visible = state[id] == true
	end
end

function HUD:pulsePower()
	Widgets.pop(self.PowerLabel, 1.06)
end

--[[
	Odpočty běží z lokálního času — server posílá profil jen občas,
	ale truhla i boosty musí tikat plynule.
]]
function HUD:refreshTimers(now: number)
	--[[
		Okno pro celý server běží na čase, ne na profilu — musí se tedy
		přepočítat i hráči, kterému zrovna nepřišel žádný profil.
	]]
	self:refreshHappy(now)

	local profile = self.Profile
	if not profile then
		return
	end

	for _, boost in Config.Boosts do
		local card = self.BoostCards[boost.Id]
		local remaining = Economy.boostRemaining(profile, boost.Id, now)

		if remaining > 0 then
			card.Subtitle.Text = `ACTIVE {Format.time(remaining)}`
			card.Subtitle.TextColor3 = Theme.Acid
		elseif Economy.dealId(now) == boost.Id then
			-- Denní nabídka: přeškrtnutá původní cena vedle nové. Bez ní
			-- vypadá sleva jako běžná cena a nikdo si jí nevšimne.
			card.Subtitle.Text = `TODAY 💎{Economy.boostPrice(boost.Id, now)}  (was {boost.Gems})`
			card.Subtitle.TextColor3 = Theme.Acid
		else
			card.Subtitle.Text = `ONLY 💎{boost.Gems}`
			card.Subtitle.TextColor3 = Theme.Gems
		end
	end

	local ready, remaining = Economy.canClaimChest(profile, now)
	self.ChestTimer.Text = if ready then "READY!" else Format.time(remaining)
	self.ChestTimer.TextColor3 = if ready then Theme.Acid else Theme.Text
end

return HUD

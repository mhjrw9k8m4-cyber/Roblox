--!strict
--[[
	HUD — trvale viditelná vrstva, poskládaná podle her v žánru:

	  vlevo nahoře     velký Power counter (hlavní číslo hry)
	  vpravo nahoře    peníze a gemy
	  vlevo            sloupec ikon: FREE / REBIRTH / TITLES / WORLDS / UPGRADES
	  vpravo           nabídky boostů za gemy
	  nahoře uprostřed odznaky aktivních boostů
	  dole uprostřed   lišta postupu k další bariéře + tečky za jednotlivé bariéry
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Build = require(Shared.Build)
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)

local Widgets = require(script.Parent.Widgets)

local Theme = Config.Theme

local HUD = {}
HUD.__index = HUD

export type Handle = typeof(setmetatable({} :: any, HUD))

function HUD.new(screen: ScreenGui): Handle
	local self = setmetatable({}, HUD)

	self.Screen = screen
	self.OnAction = nil :: ((string) -> ())?
	self.OnBuyBoost = nil :: ((string) -> ())?
	self.Profile = nil
	self.MenuButtons = {} :: { [string]: TextButton }
	self.BoostBadges = {} :: { [string]: Frame }

	self:buildCounters()
	self:buildMenu()
	self:buildBoosts()
	self:buildBoostBadges()
	self:buildProgress()

	return self
end

-- Počítadla -------------------------------------------------------------------

function HUD:buildCounters()
	-- Power je hlavní číslo hry, tak dostane i největší plochu
	local power = Widgets.panel({
		Name = "Power",
		Size = UDim2.new(0, 300, 0, 78),
		Position = UDim2.new(0, 14, 0, 14),
		Parent = self.Screen,
	})

	Widgets.label({
		Text = "POWER",
		Size = UDim2.new(1, -20, 0, 18),
		Position = UDim2.new(0, 12, 0, 8),
		Color = Theme.TextDim,
		TextSize = 15,
		Parent = power,
	})

	self.PowerLabel = Widgets.label({
		Text = "0",
		Size = UDim2.new(1, -130, 0, 42),
		Position = UDim2.new(0, 12, 0, 26),
		Color = Theme.Power,
		TextSize = 38,
		Parent = power,
	})

	self.PickupLabel = Widgets.label({
		Text = "+1",
		Size = UDim2.new(0, 110, 0, 26),
		Position = UDim2.new(1, -122, 0, 34),
		Color = Theme.Success,
		TextSize = 22,
		Align = Enum.TextXAlignment.Right,
		Parent = power,
	})

	local wallet = Instance.new("Frame")
	wallet.Name = "Wallet"
	wallet.Size = UDim2.new(0, 210, 0, 96)
	wallet.Position = UDim2.new(1, -14, 0, 14)
	wallet.AnchorPoint = Vector2.new(1, 0)
	wallet.BackgroundTransparency = 1
	wallet.Parent = self.Screen
	Widgets.list(wallet, 6)

	local function pill(icon: string, color: Color3, order: number): TextLabel
		local frame = Widgets.panel({
			Size = UDim2.new(1, 0, 0, 44),
			Position = UDim2.fromScale(0, 0),
			Parent = wallet,
		})
		frame.LayoutOrder = order

		Widgets.label({
			Text = icon,
			Size = UDim2.new(0, 34, 1, 0),
			Position = UDim2.new(0, 8, 0, 0),
			Align = Enum.TextXAlignment.Center,
			TextSize = 24,
			Parent = frame,
			Stroke = false,
		})

		return Widgets.label({
			Text = "0",
			Size = UDim2.new(1, -52, 1, 0),
			Position = UDim2.new(0, 44, 0, 0),
			Color = color,
			TextSize = 24,
			Parent = frame,
		})
	end

	self.CoinsLabel = pill("💰", Theme.Coins, 1)
	self.GemsLabel = pill("💎", Theme.Gems, 2)
end

-- Levý sloupec menu -------------------------------------------------------------

function HUD:buildMenu()
	local column = Instance.new("Frame")
	column.Name = "Menu"
	column.Size = UDim2.new(0, 168, 0, 260)
	column.Position = UDim2.new(0, 14, 0, 104)
	column.BackgroundTransparency = 1
	column.Parent = self.Screen

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(78, 78)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = column

	local entries = {
		{ Id = "chest", Icon = "🎁", Text = "FREE", Color = Theme.Accent },
		{ Id = "rebirth", Icon = "⭐", Text = "REBIRTH", Color = Color3.fromRGB(255, 92, 160) },
		{ Id = "titles", Icon = "👑", Text = "TITLES", Color = Color3.fromRGB(255, 156, 61) },
		{ Id = "worlds", Icon = "🌍", Text = "WORLDS", Color = Color3.fromRGB(88, 190, 255) },
		{ Id = "upgrades", Icon = "⚡", Text = "UPGRADES", Color = Theme.Success },
	}

	for index, entry in entries do
		local button = Widgets.iconButton({
			Icon = entry.Icon,
			Text = entry.Text,
			Color = entry.Color,
			Size = UDim2.fromOffset(78, 78),
			Parent = column,
			LayoutOrder = index,
		})

		button.MouseButton1Click:Connect(function()
			if self.OnAction then
				self.OnAction(entry.Id)
			end
		end)

		self.MenuButtons[entry.Id] = button
	end

	-- Odpočet truhly rovnou na tlačítku, ať se kvůli němu nemusí nic otvírat
	self.ChestTimer = Widgets.label({
		Text = "",
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.new(0, 0, 1, -19),
		Align = Enum.TextXAlignment.Center,
		TextSize = 13,
		Parent = self.MenuButtons.chest,
	})
end

-- Pravý sloupec s boosty ---------------------------------------------------------

function HUD:buildBoosts()
	local column = Instance.new("Frame")
	column.Name = "Boosts"
	column.Size = UDim2.new(0, 190, 0, 210)
	column.Position = UDim2.new(1, -14, 0, 122)
	column.AnchorPoint = Vector2.new(1, 0)
	column.BackgroundTransparency = 1
	column.Parent = self.Screen
	Widgets.list(column, 8)

	for index, boost in Config.Boosts do
		local card = Widgets.button({
			Text = "",
			Size = UDim2.new(1, 0, 0, 54),
			Color = Color3.fromRGB(126, 84, 224),
			Parent = column,
		})
		card.LayoutOrder = index

		Widgets.label({
			Text = `{boost.Icon} {boost.Name}`,
			Size = UDim2.new(1, -16, 0, 22),
			Position = UDim2.new(0, 8, 0, 5),
			TextSize = 17,
			Parent = card,
		})

		Widgets.label({
			Text = `ONLY 💎{boost.Gems}`,
			Size = UDim2.new(1, -16, 0, 20),
			Position = UDim2.new(0, 8, 0, 28),
			Color = Theme.Gems,
			TextSize = 16,
			Parent = card,
		})

		card.MouseButton1Click:Connect(function()
			if self.OnBuyBoost then
				self.OnBuyBoost(boost.Id)
			end
		end)
	end
end

function HUD:buildBoostBadges()
	local row = Instance.new("Frame")
	row.Name = "ActiveBoosts"
	row.Size = UDim2.new(0, 430, 0, 34)
	row.Position = UDim2.new(0.5, 0, 0, 14)
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.BackgroundTransparency = 1
	row.Parent = self.Screen
	Widgets.list(row, 8, Enum.FillDirection.Horizontal)

	for index, boost in Config.Boosts do
		local badge = Widgets.panel({
			Size = UDim2.new(0, 132, 1, 0),
			Position = UDim2.fromScale(0, 0),
			Color = Color3.fromRGB(126, 84, 224),
			Parent = row,
		})
		badge.LayoutOrder = index
		badge.Visible = false

		local label = Widgets.label({
			Text = "",
			Size = UDim2.fromScale(1, 1),
			Align = Enum.TextXAlignment.Center,
			TextSize = 16,
			Parent = badge,
		})
		label.Name = "Value"

		self.BoostBadges[boost.Id] = badge
	end
end

-- Spodní lišta postupu -------------------------------------------------------------

function HUD:buildProgress()
	local holder = Instance.new("Frame")
	holder.Name = "Progress"
	holder.Size = UDim2.new(0, 460, 0, 76)
	holder.Position = UDim2.new(0.5, 0, 1, -18)
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.BackgroundTransparency = 1
	holder.Parent = self.Screen

	self.WorldLabel = Widgets.label({
		Text = "",
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0, 0, 0, 0),
		Align = Enum.TextXAlignment.Center,
		TextSize = 19,
		Color = Theme.TextDim,
		Parent = holder,
	})

	-- Tečky = bariéry světa; zelená znamená proraženo
	local dots = Instance.new("Frame")
	dots.Name = "Dots"
	dots.Size = UDim2.new(1, 0, 0, 12)
	dots.Position = UDim2.new(0, 0, 0, 26)
	dots.BackgroundTransparency = 1
	dots.Parent = holder
	Widgets.list(dots, 5, Enum.FillDirection.Horizontal)

	self.Dots = {}
	for index = 1, Config.Track.BarrierCount do
		local dot = Instance.new("Frame")
		dot.Size = UDim2.fromOffset(12, 12)
		dot.BackgroundColor3 = Theme.PanelLight
		dot.BorderSizePixel = 0
		dot.LayoutOrder = index
		dot.Parent = dots
		Build.corner(dot, 6)
		Build.stroke(dot, Theme.Outline, 2)
		self.Dots[index] = dot
	end

	local _, fill = Widgets.progressBar({
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.new(0, 0, 0, 46),
		Color = Theme.Power,
		Parent = holder,
	})
	self.ProgressFill = fill

	self.ProgressLabel = Widgets.label({
		Text = "",
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.new(0, 0, 0, 46),
		Align = Enum.TextXAlignment.Center,
		TextSize = 17,
		Parent = holder,
	})
end

-- Aktualizace ---------------------------------------------------------------------

function HUD:setProfile(profile)
	self.Profile = profile

	self.CoinsLabel.Text = Format.short(profile.Coins)
	self.GemsLabel.Text = Format.short(profile.Gems)
	self.PickupLabel.Text = `+{Format.short(profile.PickupValue or 1)}`

	local world = Config.Worlds[profile.WorldIndex]
	if world then
		self.WorldLabel.Text = world.Name:upper()
	end

	for index, dot in self.Dots do
		dot.BackgroundColor3 = if index < profile.Barrier then Theme.Success else Theme.PanelLight
	end

	self:setPower(profile.Power)
	self:refreshTimers(profile.ServerTime or os.time())
end

function HUD:setPower(power: number)
	self.PowerLabel.Text = Format.short(power)

	local profile = self.Profile
	if not profile then
		return
	end

	local barrier = math.min(profile.Barrier, Config.Track.BarrierCount)
	local needed = Config.barrierPower(profile.WorldIndex, barrier)

	Widgets.setProgress(self.ProgressFill, power / math.max(needed, 1))

	if power >= needed then
		self.ProgressFill.BackgroundColor3 = Theme.Success
		self.ProgressLabel.Text = "SMASH THE WALL!"
	else
		self.ProgressFill.BackgroundColor3 = Theme.Power
		self.ProgressLabel.Text = `{Format.short(power)} / {Format.short(needed)}`
	end
end

function HUD:pulsePower()
	Widgets.pop(self.PowerLabel, 1.15)
end

--[[
	Odpočty běží z lokálního času — server posílá profil jen občas,
	ale truhla i boosty musí tikat plynule.
]]
function HUD:refreshTimers(now: number)
	local profile = self.Profile
	if not profile then
		return
	end

	for _, boost in Config.Boosts do
		local badge = self.BoostBadges[boost.Id]
		local remaining = Economy.boostRemaining(profile, boost.Id, now)

		badge.Visible = remaining > 0
		if remaining > 0 then
			local label = badge:FindFirstChild("Value") :: TextLabel
			label.Text = `{boost.Icon} {Format.time(remaining)}`
		end
	end

	local ready, remaining = Economy.canClaimChest(profile, now)
	self.ChestTimer.Text = if ready then "READY!" else Format.time(remaining)
	self.ChestTimer.TextColor3 = if ready then Theme.Success else Theme.Text
end

return HUD

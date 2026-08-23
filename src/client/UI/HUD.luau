--!strict
--[[
	HUD — trvale viditelné informace a hlavní ovládání.

	Nahoře peníze, úroveň a příjem za sekundu.
	Uprostřed dole velké tlačítko na sekání (mobil) a nad ním
	stav materiálu s combem.
	Vpravo sloupec tlačítek do panelů.
]]

local TweenService = game:GetService("TweenService")

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
	self.Buttons = {} :: { [string]: TextButton }
	self.OnAction = nil :: ((string) -> ())?
	self.OnStrike = nil :: (() -> ())?
	self.Combo = 0

	self:buildTopBar()
	self:buildStatusBar()
	self:buildSideButtons()
	self:buildStrikeButton()

	return self
end

-- Horní lišta: peníze, úroveň, příjem -------------------------------------

function HUD:buildTopBar()
	local bar = Widgets.panel({
		Name = "HorníLišta",
		Size = UDim2.new(0, 320, 0, 96),
		Position = UDim2.new(0, 16, 0, 16),
		Parent = self.Screen,
	})
	Build.stroke(bar, Theme.PanelLight, 2, 0.3)

	self.CoinsLabel = Widgets.label({
		Text = "💰 0",
		Size = UDim2.new(1, -24, 0, 34),
		Position = UDim2.new(0, 12, 0, 8),
		Color = Theme.Gold,
		Font = Enum.Font.FredokaOne,
		TextSize = 30,
		Parent = bar,
	})

	self.RateLabel = Widgets.label({
		Text = "0 /s",
		Size = UDim2.new(0, 120, 0, 18),
		Position = UDim2.new(1, -132, 0, 14),
		Color = Theme.TextDim,
		TextSize = 14,
		Align = Enum.TextXAlignment.Right,
		Parent = bar,
	})

	self.LevelLabel = Widgets.label({
		Text = "Úroveň 1",
		Size = UDim2.new(1, -24, 0, 16),
		Position = UDim2.new(0, 12, 0, 46),
		Color = Theme.TextDim,
		TextSize = 14,
		Parent = bar,
	})

	local _, fill = Widgets.progressBar({
		Size = UDim2.new(1, -24, 0, 12),
		Position = UDim2.new(0, 12, 0, 68),
		Color = Theme.Accent2,
		Parent = bar,
	})
	self.XpFill = fill

	-- Rebirth odznak vedle lišty
	self.RebirthBadge = Widgets.panel({
		Name = "Rebirthy",
		Size = UDim2.new(0, 96, 0, 40),
		Position = UDim2.new(0, 348, 0, 16),
		Color = Theme.PanelLight,
		Parent = self.Screen,
	})
	self.RebirthLabel = Widgets.label({
		Text = "⭐ 0",
		Size = UDim2.fromScale(1, 1),
		Color = Theme.Accent,
		Font = Enum.Font.FredokaOne,
		TextSize = 20,
		Align = Enum.TextXAlignment.Center,
		Parent = self.RebirthBadge,
	})
end

-- Stav materiálu a combo ---------------------------------------------------

function HUD:buildStatusBar()
	local holder = Widgets.panel({
		Name = "StavMateriálu",
		Size = UDim2.new(0, 340, 0, 64),
		Position = UDim2.new(0.5, 0, 1, -190),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = self.Screen,
	})
	self.StatusHolder = holder

	self.ObjectLabel = Widgets.label({
		Text = "Mýdlo",
		Size = UDim2.new(1, -24, 0, 20),
		Position = UDim2.new(0, 12, 0, 8),
		TextSize = 16,
		Font = Enum.Font.GothamBold,
		Parent = holder,
	})

	self.ComboLabel = Widgets.label({
		Text = "",
		Size = UDim2.new(0, 140, 0, 20),
		Position = UDim2.new(1, -152, 0, 8),
		Color = Theme.Gold,
		Font = Enum.Font.FredokaOne,
		TextSize = 18,
		Align = Enum.TextXAlignment.Right,
		Parent = holder,
	})

	local _, fill = Widgets.progressBar({
		Size = UDim2.new(1, -24, 0, 16),
		Position = UDim2.new(0, 12, 0, 36),
		Color = Theme.Success,
		Parent = holder,
	})
	self.IntegrityFill = fill
end

-- Boční tlačítka ------------------------------------------------------------

function HUD:buildSideButtons()
	local column = Instance.new("Frame")
	column.Name = "Menu"
	column.Size = UDim2.new(0, 132, 0, 320)
	column.Position = UDim2.new(1, -148, 0.5, -160)
	column.BackgroundTransparency = 1
	column.Parent = self.Screen

	Widgets.list(column, 8)

	local entries = {
		{ Id = "tools", Text = "🔪  Nože", Color = Theme.Accent },
		{ Id = "objects", Text = "🧊  Materiály", Color = Theme.Accent2 },
		{ Id = "upgrades", Text = "⚡  Vylepšení", Color = Theme.Success },
		{ Id = "rewards", Text = "🎁  Odměny", Color = Theme.Gold },
		{ Id = "rebirth", Text = "⭐  Rebirth", Color = Theme.Danger },
	}

	for index, entry in entries do
		local button = Widgets.button({
			Text = entry.Text,
			Size = UDim2.new(1, 0, 0, 48),
			Color = entry.Color,
			TextSize = 17,
			Parent = column,
		})
		button.LayoutOrder = index
		button.TextXAlignment = Enum.TextXAlignment.Center

		button.MouseButton1Click:Connect(function()
			if self.OnAction then
				self.OnAction(entry.Id)
			end
		end)

		self.Buttons[entry.Id] = button
	end

	-- Odznak "máš nevyzvednutou odměnu"
	local badge = Instance.new("Frame")
	badge.Name = "Odznak"
	badge.Size = UDim2.fromOffset(14, 14)
	badge.Position = UDim2.new(1, -8, 0, 6)
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.BackgroundColor3 = Theme.Danger
	badge.BorderSizePixel = 0
	badge.Visible = false
	badge.Parent = self.Buttons.rewards
	Build.corner(badge, 7)
	self.RewardBadge = badge
end

-- Velké tlačítko na sekání (hlavně pro mobil) ------------------------------

function HUD:buildStrikeButton()
	local button = Widgets.button({
		Text = "SEKNI",
		Size = UDim2.new(0, 200, 0, 84),
		Position = UDim2.new(0.5, 0, 1, -104),
		AnchorPoint = Vector2.new(0.5, 0),
		Color = Theme.Accent,
		Font = Enum.Font.FredokaOne,
		TextSize = 30,
		Radius = 18,
		Parent = self.Screen,
	})
	button.TextXAlignment = Enum.TextXAlignment.Center
	Build.gradient(button, Theme.Accent, Theme.Accent:Lerp(Color3.new(0, 0, 0), 0.25))

	-- Držení = opakované seky; klikat po jedné by u grindu bylo utrpení.
	local holding = false

	button.MouseButton1Down:Connect(function()
		holding = true
		task.spawn(function()
			while holding do
				if self.OnStrike then
					self.OnStrike()
				end
				task.wait(0.05)
			end
		end)
	end)

	local function stop()
		holding = false
	end

	button.MouseButton1Up:Connect(stop)
	button.MouseLeave:Connect(stop)

	self.StrikeButton = button
end

-- Aktualizace ---------------------------------------------------------------

function HUD:setProfile(profile)
	self.Profile = profile

	self.CoinsLabel.Text = `💰 {Format.short(profile.Coins)}`
	self.RateLabel.Text = `{Format.short(profile.CoinsPerSecond)} /s`
	self.RebirthLabel.Text = `⭐ {profile.Rebirths}`

	local progress, needed = Economy.levelProgress(profile)
	if profile.Level >= Config.Level.MaxLevel then
		self.LevelLabel.Text = `Úroveň {profile.Level} — MAX`
	else
		self.LevelLabel.Text =
			`Úroveň {profile.Level}  <font color="#8A85A8">{Format.short(profile.Xp)}/{Format.short(needed)} XP</font>`
	end
	Widgets.setProgress(self.XpFill, progress)

	local object = Config.object(profile.EquippedObject)
	if object then
		self.ObjectLabel.Text = object.Name
	end

	if profile.MaxIntegrity > 0 then
		Widgets.setProgress(self.IntegrityFill, profile.Integrity / profile.MaxIntegrity)
	end
end

-- Jen peníze: volá se po každé ráně, celý profil kvůli tomu chodit nemusí
function HUD:setCoins(coins: number)
	if self.Profile then
		self.Profile.Coins = coins
	end
	self.CoinsLabel.Text = `💰 {Format.short(coins)}`
end

function HUD:setIntegrity(ratio: number)
	Widgets.setProgress(self.IntegrityFill, ratio)

	-- Barva lišty se mění, jak se materiál blíží rozpadu
	local color = Theme.Success:Lerp(Theme.Danger, 1 - math.clamp(ratio, 0, 1))
	self.IntegrityFill.BackgroundColor3 = color
end

function HUD:setCombo(combo: number, multiplier: number)
	self.Combo = combo

	if combo <= 1 then
		self.ComboLabel.Text = ""
		return
	end

	self.ComboLabel.Text = `{combo}× KOMBO  {Format.multiplier(multiplier)}`

	-- Krátký "pop", aby bylo combo cítit
	self.ComboLabel.TextSize = 24
	TweenService:Create(self.ComboLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad), { TextSize = 18 }):Play()
end

function HUD:setRewardBadge(visible: boolean)
	self.RewardBadge.Visible = visible
end

return HUD

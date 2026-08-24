--!strict
--[[
	Onboarding — první sezení.

	Retence prvního dne je podle Robloxu 2026 nejsilnější signál v celém
	doporučování. Hráč, který za první minutu nepochopí smyčku, odejde
	a už se nevrátí — a přesně to je ta minuta, kterou tenhle modul řeší.

	Vede jen dokud hráč neprorazí první zeď. Pak zmizí a nikdy se nevrátí,
	protože nápověda, kterou nejde vypnout, je horší než žádná.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Track = require(Shared.Track)

local Style = require(script.Parent.UI.Style)
local Widgets = require(script.Parent.UI.Widgets)

local Theme = Config.Theme
local player = Players.LocalPlayer

local Onboarding = {}

local STEPS = {
	{ Id = "collect", Text = "Walk over the glowing +1 cubes to build POWER" },
	{ Id = "smash", Text = "You have enough! Run into the wall to SMASH it" },
	{ Id = "shop", Text = "Spend coins on UPGRADES — every +1 gets stronger" },
}

local screen: ScreenGui? = nil
local card: Frame? = nil
local label: TextLabel? = nil
local arrow: BasePart? = nil
local step = 0
local active = false

local function build(parent: ScreenGui)
	local holder = Widgets.panel({
		Name = "Onboarding",
		Size = UDim2.new(0, 460, 0, 62),
		Position = UDim2.new(0.5, 0, 0, 58),
		AnchorPoint = Vector2.new(0.5, 0),
		Color = Theme.Violet,
		Radius = Style.Radius.Card,
		Parent = parent,
	})

	label = Widgets.label({
		Text = "",
		Size = UDim2.new(1, -24, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		Align = Enum.TextXAlignment.Center,
		TextSize = 19,
		Parent = holder,
	})

	card = holder
end

--[[
	Šipka nad další zdí. Text sám o sobě neřekne KAM — a v chodbě, kde
	všechno svítí, se cíl snadno ztratí.
]]
local function buildArrow()
	if arrow then
		return
	end

	local part = Instance.new("Part")
	part.Name = "OnboardingArrow"
	part.Size = Vector3.new(4, 4, 4)
	part.Shape = Enum.PartType.Ball
	part.Color = Theme.Acid
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 0.2
	part.Parent = workspace

	local light = Instance.new("PointLight")
	light.Color = Theme.Acid
	light.Brightness = 3
	light.Range = 20
	light.Parent = part

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(6, 3)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 400
	billboard.Adornee = part
	billboard.Parent = part

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Style.Font.Display
	text.Text = "▼"
	text.TextColor3 = Theme.Acid
	text.TextScaled = true
	text.Parent = billboard

	arrow = part
end

local function clearArrow()
	if arrow then
		arrow:Destroy()
		arrow = nil
	end
end

local function setStep(index: number)
	if index == step or not label or not card then
		return
	end

	step = index
	local entry = STEPS[index]
	if not entry then
		return
	end

	label.Text = entry.Text
	Widgets.pop(card, 1.06)
end

function Onboarding.finish()
	if not active then
		return
	end
	active = false

	clearArrow()

	if card then
		local fade = TweenInfo.new(0.35)
		TweenService:Create(card, fade, { BackgroundTransparency = 1 }):Play()
		if label then
			TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
		end
		task.delay(0.5, function()
			if screen then
				screen:Destroy()
				screen = nil
			end
		end)
	end
end

--[[
	Spustí se jen pro hráče, který ještě neprorazil ani jednu zeď.
	Vrácený `update` pak dostává profil z hlavní smyčky.
]]
function Onboarding.start(parent: ScreenGui, profile)
	if profile.Smashes > 0 then
		return
	end

	active = true
	screen = parent
	build(parent)
	buildArrow()
	setStep(1)

	local elapsed = 0
	local connection
	connection = RunService.Heartbeat:Connect(function(deltaTime)
		if not active then
			connection:Disconnect()
			return
		end

		elapsed += deltaTime

		if arrow then
			local target = Track.barrierPosition(
				Onboarding.WorldIndex or 1,
				Onboarding.Barrier or 1
			)
			arrow.Position = target + Vector3.new(0, 16 + math.sin(elapsed * 3) * 1.2, 0)
		end
	end)
end

--[[
	Volá se při každé změně profilu. Krok se odvozuje ze stavu hry,
	ne z časovače — nápověda tak nikdy nepředbíhá to, co hráč zrovna umí.
]]
function Onboarding.update(profile)
	if not active then
		return
	end

	Onboarding.WorldIndex = profile.WorldIndex
	Onboarding.Barrier = profile.Barrier

	if profile.Smashes > 0 then
		Onboarding.finish()
		return
	end

	local needed = Config.barrierPower(profile.WorldIndex, profile.Barrier)
	setStep(if profile.Power >= needed then 2 else 1)
end

return Onboarding

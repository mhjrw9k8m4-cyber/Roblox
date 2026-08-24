--!strict
--[[
	Milestone — velké okamžiky, které vidí celý server.

	Rebirth byl doteď jeden řádek v toastu. Přitom je to nejdražší
	rozhodnutí ve hře: hráč dobrovolně přijde o všechno, co nagrindoval.
	Když za to nedostane obřad, vypadá to jako chyba, ne jako odměna —
	a příště do toho nepůjde.

	Modul má dvě poloviny, a ta druhá je důležitější:

	  * **Vlastní okamžik** — záblesk, sloup světla, rázová vlna a nápis
	    přes celou obrazovku. Trvá dvě vteřiny, během kterých se nedá
	    dělat nic jiného než se dívat.
	  * **Cizí okamžik** — proužek ve výpisu vlevo: "Kdosi právě udělal
	    rebirth #12". Tohle je ten skutečný motor žánru. Hráč vidí, že
	    ostatní postupují, a nechce zůstat pozadu.

	Cizí okamžiky se schválně nedoprovázejí zvukem ani zábleskem. Na plném
	serveru by se z toho stal rámus, ve kterém by zanikl ten vlastní.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Build = require(Shared.Build)
local Config = require(Shared.Config)

local CameraFX = require(script.Parent.CameraFX)
local SoundKit = require(script.Parent.SoundKit)

local Style = require(script.Parent.UI.Style)

local player = Players.LocalPlayer

local Milestone = {}
Milestone.__index = Milestone

export type Payload = {
	Kind: string, -- "rebirth" | "world" | "squishy"
	UserId: number,
	Who: string,
	Text: string,
	Big: string?, -- co se napíše přes celou obrazovku (jen vlastní)
	Color: Color3?,
}

export type Handle = typeof(setmetatable(
	{} :: {
		Feed: Frame,
		Screen: ScreenGui,
		Lines: { Frame },
	},
	Milestone
))

--[[
	Barvy podle druhu. Rebirth je fialový (jako celá hra), svět zlatý
	(peníze), hračka tyrkysová — hráč pozná druh dřív, než
	dočte text.
]]
local KIND_COLOR: { [string]: Color3 } = {
	rebirth = Config.Theme.Violet,
	world = Config.Theme.Gold,
	squishy = Config.Theme.Gems,
}

--[[
	Zvuk podle druhu. Rebirth má ten nejtěžší, protože je nejdražší;
	svět fanfáru po dokončení; hračka jen cinknutí — tu si hráč
	show odbyla v panelu při nákupu.
]]
local KIND_SOUND: { [string]: string } = {
	rebirth = "Rebirth",
	world = "WorldClear",
	squishy = "Purchase",
}

local KIND_ICON: { [string]: string } = {
	rebirth = "♻",
	world = "🌍",
	squishy = "🧸",
}

local MAX_LINES = 4

function Milestone.new(screen: ScreenGui): Handle
	--[[
		Výpis sedí vlevo nahoře pod HUD. Vpravo jsou tlačítka panelů,
		uprostřed toasty — tohle je jediné místo, kde nic nepřekáží.
	]]
	local feed = Instance.new("Frame")
	feed.Name = "MilestoneFeed"
	feed.BackgroundTransparency = 1
	feed.AnchorPoint = Vector2.new(0, 0)
	feed.Position = UDim2.new(0, 12, 0, 118)
	feed.Size = UDim2.new(0, 300, 0, 140)
	feed.ZIndex = 40
	feed.Parent = screen

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = feed

	return setmetatable({
		Feed = feed,
		Screen = screen,
		Lines = {},
	}, Milestone) :: Handle
end

--[[
	Proužek ve výpisu. Přijíždí zleva, chvíli visí a odjede zpátky —
	tedy nikdy nezmizí skokem, protože pak si hráč není jistý, jestli
	tam vůbec něco bylo.
]]
function Milestone.pushLine(self: Handle, payload: Payload)
	local color = payload.Color or KIND_COLOR[payload.Kind] or Config.Theme.Cyan

	local line = Instance.new("Frame")
	line.Name = "Line"
	line.BackgroundColor3 = Config.Theme.PanelDeep
	line.BackgroundTransparency = 0.15
	line.Size = UDim2.new(1, 0, 0, 30)
	line.Position = UDim2.new(-1.2, 0, 0, 0)
	line.ZIndex = 41
	line.Parent = self.Feed

	Style.corner(line, 8)
	Style.stroke(line, color, 2)

	-- Barevný pruh u levé hrany: druh se pozná i periferním viděním
	local edge = Instance.new("Frame")
	edge.BackgroundColor3 = color
	edge.BorderSizePixel = 0
	edge.Size = UDim2.new(0, 4, 1, -8)
	edge.Position = UDim2.new(0, 4, 0, 4)
	edge.ZIndex = 42
	edge.Parent = line
	Style.corner(edge, 2)

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -20, 1, 0)
	label.Position = UDim2.new(0, 14, 0, 0)
	label.Font = Style.Font.Body
	label.TextSize = 14
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.RichText = true
	label.Text = `{KIND_ICON[payload.Kind] or "★"} {payload.Text}`
	label.ZIndex = 42
	label.Parent = line
	Style.textOutline(label, 1.5)

	table.insert(self.Lines, line)

	-- Nejstarší proužek odchází, aby výpis nerostl přes půl obrazovky
	while #self.Lines > MAX_LINES do
		local oldest = table.remove(self.Lines, 1)
		if oldest then
			oldest:Destroy()
		end
	end

	for index, existing in self.Lines do
		existing.LayoutOrder = index
	end

	TweenService:Create(line, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, 0, 0, 0),
	}):Play()

	task.delay(6, function()
		if not line.Parent then
			return
		end

		TweenService:Create(line, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(-1.2, 0, 0, 0),
			BackgroundTransparency = 1,
		}):Play()

		task.wait(0.4)

		local at = table.find(self.Lines, line)
		if at then
			table.remove(self.Lines, at)
		end
		line:Destroy()
	end)
end

--[[
	Nápis přes obrazovku. Přiletí zvětšený a smrskne se na místo —
	pohyb směrem k hráči čte oko jako "tohle je důležité", zatímco
	nafukování ven vypadá jako odchod.
]]
local function bigText(screen: ScreenGui, text: string, color: Color3)
	local label = Instance.new("TextLabel")
	label.Name = "MilestoneBig"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.36)
	label.Size = UDim2.fromScale(0.9, 0.16)
	label.Font = Style.Font.Display
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.ZIndex = 90
	label.Parent = screen

	local stroke = Style.textOutline(label, 5)

	local scale = Instance.new("UIScale")
	scale.Scale = 3.2
	scale.Parent = label

	TweenService:Create(scale, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()

	task.delay(1.5, function()
		TweenService:Create(label, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
		}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		TweenService:Create(scale, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Scale = 1.4,
		}):Play()

		Debris:AddItem(label, 0.6)
	end)
end

--[[
	Rázová vlna u nohou. Prstenec, který se roztáhne a zmizí — nejlevnější
	způsob, jak dát okamžiku měřítko: hráč vidí, jak daleko to "dosáhlo".
]]
local function shockwave(position: Vector3, color: Color3)
	local ring = Build.part({
		Name = "Vlna",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 6, 6),
		Position = position,
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.2,
		CanCollide = false,
		CastShadow = false,
		Parent = Workspace,
	})
	-- Válec leží na boku, aby z něj byl prstenec na zemi, ne sloupek
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))

	TweenService:Create(ring, TweenInfo.new(0.9, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = Vector3.new(1, 90, 90),
		Transparency = 1,
	}):Play()

	Debris:AddItem(ring, 1)
end

--[[
	Sloup světla. Stojí na místě hráče a stoupá — u rebirthu je vysoký
	tak, že ho na trati vidí i ostatní, takže je hned jasné, kdo za to
	může.
]]
local function pillar(position: Vector3, color: Color3)
	local beam = Build.part({
		Name = "Sloup",
		Size = Vector3.new(10, 240, 10),
		Position = position + Vector3.new(0, 120, 0),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.45,
		CanCollide = false,
		CastShadow = false,
		Parent = Workspace,
	})

	TweenService:Create(beam, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.5, 320, 0.5),
		Transparency = 1,
	}):Play()

	local attachment = Instance.new("Attachment")
	attachment.Parent = beam

	local rise = Instance.new("ParticleEmitter")
	rise.Color = ColorSequence.new(color)
	rise.LightEmission = 1
	rise.LightInfluence = 0
	rise.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2.4),
		NumberSequenceKeypoint.new(1, 0),
	})
	rise.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	rise.Lifetime = NumberRange.new(0.8, 1.6)
	rise.Speed = NumberRange.new(30, 70)
	rise.SpreadAngle = Vector2.new(12, 12)
	rise.Rate = 0
	rise.Parent = attachment
	rise:Emit(180)

	Debris:AddItem(beam, 2)
end

--[[
	Celý obřad. Volá se jen na vlastní okamžik — cizí dostane proužek.
]]
function Milestone.celebrate(self: Handle, payload: Payload)
	local color = payload.Color or KIND_COLOR[payload.Kind] or Config.Theme.Violet

	CameraFX.flash(0.7, color)
	CameraFX.shake(2.2)
	SoundKit.playNamed(KIND_SOUND[payload.Kind] or "Rebirth")

	if payload.Big then
		bigText(self.Screen, payload.Big, color)
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local base = root.Position - Vector3.new(0, 2.5, 0)
		pillar(base, color)
		shockwave(base, color)

		-- Druhá vlna se zpožděním: jedna vypadá jako efekt, dvě jako událost
		task.delay(0.18, function()
			shockwave(base, color)
		end)
	end
end

--[[
	Vstupní bod pro server. Rozhoduje jediná věc — jestli je to můj
	okamžik, nebo cizí.
]]
function Milestone.play(self: Handle, payload: Payload)
	--[[
		Obřad se pouští jen tam, kde je co ukázat. Hračka `Big` nemá:
		nákup si odbyl svoje v panelu a přidat k němu sloup světla
		a rázovou vlnu by bylo přehnané.
	]]
	if payload.UserId == player.UserId and payload.Big then
		self:celebrate(payload)
	end

	self:pushLine(payload)
end

return Milestone

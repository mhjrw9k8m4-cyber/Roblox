--!strict
--[[
	Welcome — první tři vteřiny vracejícího se hráče.

	Roblox od konce roku 2025 řadí hry hlavně podle NÁVRATNOSTI: druhé,
	kratší sezení do dvou dnů váží víc než dlouhé první. Okamžik, kdy se
	hráč vrátí, je proto ten nejcennější v celé hře — a do teď na něj
	připadal jeden toast v rohu, který zmizel za pár vteřin.

	Karta dělá dvě věci, které toast neuměl:

	  * pojmenuje, co na hráče čekalo (offline výdělek a jak dlouho byl
	    pryč) — návrat se tím vyplatí, ne jen povolí,
	  * pošle ho rovnou do denní odměny. Právě ta vyrábí návraty další
	    dny, a hráč, který ji po přihlášení nevidí, si ji nevybere.

	Zavírá se sama i tlačítkem. Karta, kterou nejde odklepnout, stojí
	v cestě přesně tomu, kvůli čemu se hráč vrátil.
]]

local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)

local Style = require(script.Parent.Style)
local Widgets = require(script.Parent.Widgets)

local Theme = Config.Theme

local Welcome = {}

-- Jak dlouho karta vydrží, když ji hráč neodklepne
local LINGER_SECONDS = 9

local card: Frame? = nil
local closing = false

--[[
	Zavře kartu. `only` je pojistka pro odložené zavření: časovač
	nastavený na starou kartu nesmí sundat tu, která se mezitím
	objevila místo ní.
]]
local function dismiss(only: Frame?)
	local frame = card
	if not frame or closing then
		return
	end
	if only and only ~= frame then
		return
	end
	closing = true

	local fade = TweenInfo.new(0.3, Enum.EasingStyle.Quad)
	TweenService:Create(frame, fade, {
		BackgroundTransparency = 1,
		Position = frame.Position + UDim2.fromOffset(0, 40),
	}):Play()

	for _, child in frame:GetDescendants() do
		if child:IsA("TextLabel") or child:IsA("TextButton") then
			TweenService:Create(child, fade, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		end
	end

	task.delay(0.4, function()
		if card then
			card:Destroy()
			card = nil
		end
		closing = false
	end)
end

--[[
	Ven kvůli testu i kvůli tomu, aby šla karta zavřít odjinud — třeba
	když hráč hned otevře panel a karta by mu stála v cestě.
]]
function Welcome.dismiss()
	dismiss()
end

-- Stojí tu karta? Test se jinak nemá čeho chytit.
function Welcome.visible(): boolean
	return card ~= nil and not closing
end

--[[
	Ukáže kartu. `onDaily` je cesta do denní odměny — bez ní by karta
	jen chválila návrat a nikam nevedla.
]]
function Welcome.show(parent: ScreenGui, payload: { Coins: number, Seconds: number }, onDaily: () -> ())
	--[[
		Předchozí karta se ruší HNED, ne přelivem.

		Zavření přes `dismiss` nechá kartu ještě čtyři desetiny vteřiny
		ve stromu, aby stihla vyblednout — jenže po tu dobu je pořád
		klikatelná a leží pod tou novou. Když jednu kartu nahrazuje
		druhá, není co vybledávat.
	]]
	if card then
		card:Destroy()
		card = nil
	end
	closing = false

	local frame = Widgets.panel({
		Name = "Welcome",
		Size = UDim2.new(0, 380, 0, 210),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Panel,
		Radius = Style.Radius.Card,
		Parent = parent,
	})
	card = frame

	Widgets.label({
		Text = "<b>WELCOME BACK</b>",
		Size = UDim2.new(1, -24, 0, 40),
		Position = UDim2.fromOffset(12, 14),
		Align = Enum.TextXAlignment.Center,
		Color = Theme.Gold,
		TextSize = 30,
		Parent = frame,
	}).Font = Style.Font.Display

	Widgets.label({
		Text = `You were away for {Format.time(payload.Seconds)}`,
		Size = UDim2.new(1, -24, 0, 24),
		Position = UDim2.fromOffset(12, 56),
		Align = Enum.TextXAlignment.Center,
		Color = Theme.TextDim,
		TextSize = 17,
		Parent = frame,
	})

	--[[
		Částka je největší věc na kartě. Je to jediný důvod, proč se na
		ni hráč dívá, a proto nesmí být stejně velká jako popisek nad ní.
	]]
	Widgets.label({
		Text = `<b>+{Format.short(payload.Coins)} 💰</b>`,
		Size = UDim2.new(1, -24, 0, 52),
		Position = UDim2.fromOffset(12, 84),
		Align = Enum.TextXAlignment.Center,
		Color = Theme.Coins,
		TextSize = 42,
		Parent = frame,
	}).Font = Style.Font.Display

	local button = Widgets.button({
		Text = "CLAIM DAILY REWARD",
		Size = UDim2.new(1, -48, 0, 46),
		Position = UDim2.new(0.5, 0, 1, -20),
		AnchorPoint = Vector2.new(0.5, 1),
		Color = Theme.Violet,
		TextSize = 20,
		Parent = frame,
	})

	button.Activated:Connect(function()
		dismiss()
		onDaily()
	end)

	Widgets.pop(frame, 1.08)

	--[[
		Zmizí i sama. Hráč, který se vrátil, chce hrát — karta, která
		čeká na kliknutí, mu v tom brání přesně v tu chvíli.
	]]
	task.delay(LINGER_SECONDS, function()
		dismiss(frame)
	end)
end

return Welcome

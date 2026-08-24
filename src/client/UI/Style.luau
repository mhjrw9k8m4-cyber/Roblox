--!strict
--[[
	Style — vizuální jazyk hry na jednom místě.

	Odkoukáno z největších her v žánru. Ty všechny stojí na pěti věcech,
	a když jedna chybí, UI hned vypadá jako prototyp:

	  1. DVOJITÝ OBRYS — tmavý vnější (4 px) a světlý vnitřní. Bez toho
	     se prvky slévají s pozadím.
	  2. SVISLÝ GRADIENT na každé ploše, světlejší nahoře. Dělá "plast".
	  3. STUD TEXTURA — jemná mřížka teček na panelech. To je ten
	     rozpoznatelný Roblox "kostičkový" pocit.
	  4. TLUSTÝ OBRYS PÍSMA. Text bez obtahu v téhle paletě zmizí.
	  5. KULATÉ TUČNÉ PÍSMO (FredokaOne), velká čísla ještě tučnější.

	Tenhle modul dává primitiva; `Widgets` z nich skládá komponenty.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local Style = {}

Style.Palette = Config.Theme

Style.Font = {
	-- Kulaté tučné písmo, kterým je celý žánr psaný
	Body = Enum.Font.FredokaOne,
	-- Na obří čísla, ať mají ještě větší váhu
	Display = Enum.Font.LuckiestGuy,
	-- Jediné místo pro drobný popisný text
	Detail = Enum.Font.GothamBold,
}

Style.Outline = {
	Thick = 4,
	Normal = 3,
	Thin = 2,
	Text = 3,
}

Style.Radius = {
	Panel = 20,
	Card = 14,
	Chip = 10,
	Tile = 16,
}

-- Základní primitiva ------------------------------------------------------------

function Style.corner(gui: GuiObject, radius: number): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = gui
	return corner
end

function Style.stroke(gui: GuiObject, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = gui
	return stroke
end

--[[
	Svislý gradient. `lift` říká, o kolik je horní hrana světlejší —
	tímhle jediným číslem se dá naladit, jestli prvek působí plasticky
	nebo plochce.
]]
function Style.gradient(gui: GuiObject, base: Color3, lift: number, drop: number?): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, base:Lerp(Color3.new(1, 1, 1), lift)),
		ColorSequenceKeypoint.new(0.5, base),
		ColorSequenceKeypoint.new(1, base:Lerp(Color3.new(0, 0, 0), drop or lift * 0.6)),
	})
	gradient.Parent = gui
	return gradient
end

--[[
	Vnitřní světlý rámeček. Dělá se přes samostatný Frame, protože druhá
	UIStroke na stejném prvku se s tou první přebíjí — Roblox respektuje
	jen jednu.
]]
function Style.bevel(gui: GuiObject, color: Color3, inset: number, radius: number): Frame
	local bevel = Instance.new("Frame")
	bevel.Name = "Bevel"
	bevel.Size = UDim2.new(1, -inset * 2, 1, -inset * 2)
	bevel.Position = UDim2.fromOffset(inset, inset)
	bevel.BackgroundTransparency = 1
	bevel.ZIndex = gui.ZIndex
	bevel.Parent = gui

	Style.corner(bevel, math.max(radius - inset, 4))
	local stroke = Style.stroke(bevel, color, 2)
	stroke.Transparency = 0.45

	return bevel
end

--[[
	Mřížka teček ("studs"), kterou mají panely v každé velké hře.

	Kreslí se z malých Frame prvků, ne z obrázku — nahraná textura by byla
	cizí asset a v cizí hře by se nemusela načíst. Počet je proto zastropovaný:
	na velkém panelu se buňka zvětší, aby se nikdy nevyrobily stovky prvků.
]]
function Style.studs(parent: GuiObject, size: Vector2, options: {
	Cell: number?,
	Color: Color3?,
	Transparency: number?,
}?)
	local opts = options or {}
	local cell = opts.Cell or 26
	local maxDots = 180

	-- Buňku raději zvětšíme, než abychom vyrobili víc prvků než je únosné
	while (size.X // cell) * (size.Y // cell) > maxDots do
		cell += 4
	end

	local holder = Instance.new("Frame")
	holder.Name = "Studs"
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.ClipsDescendants = true
	holder.ZIndex = parent.ZIndex
	holder.Parent = parent

	-- Bez zaoblení by tečky vykoukly za rohy panelu
	local parentCorner = parent:FindFirstChildOfClass("UICorner")
	if parentCorner then
		Style.corner(holder, parentCorner.CornerRadius.Offset)
	end

	local dotSize = math.max(cell * 0.34, 4)
	local color = opts.Color or Color3.new(1, 1, 1)
	local transparency = opts.Transparency or 0.9

	local columns = math.floor(size.X / cell)
	local rows = math.floor(size.Y / cell)

	for row = 0, rows do
		for column = 0, columns do
			local dot = Instance.new("Frame")
			dot.Size = UDim2.fromOffset(dotSize, dotSize)
			dot.Position = UDim2.fromOffset(
				math.floor(cell * (column + 0.5) - dotSize / 2),
				math.floor(cell * (row + 0.5) - dotSize / 2)
			)
			dot.BackgroundColor3 = color
			dot.BackgroundTransparency = transparency
			dot.BorderSizePixel = 0
			dot.ZIndex = parent.ZIndex
			dot.Parent = holder
			Style.corner(dot, math.floor(dotSize / 2))
		end
	end

	return holder
end

--[[
	Obrys písma. Vestavěný TextStroke je jednopixelový a v téhle paletě
	se ztratí, takže se používá UIStroke v režimu Contextual — ten na
	textovém prvku obtahuje písmo, ne rámeček.
]]
function Style.textOutline(label: TextLabel | TextButton, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = Style.Palette.Ink
	stroke.Thickness = thickness or Style.Outline.Text
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	return stroke
end

--[[
	Stejné jako `studs`, ale počká na skutečný rozměr.

	Hned po vytvoření je AbsoluteSize nulový — layout ještě neproběhl —
	takže by se mřížka spočítala z nuly a nevykreslila nic.
]]
function Style.studsWhenSized(parent: GuiObject, options: { Cell: number?, Color: Color3?, Transparency: number? }?)
	local function draw()
		local size = parent.AbsoluteSize
		if size.X < 8 or size.Y < 8 then
			return false
		end
		Style.studs(parent, size, options)
		return true
	end

	if draw() then
		return
	end

	local connection
	connection = parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if draw() then
			connection:Disconnect()
		end
	end)
end

-- Barevná pomoc -----------------------------------------------------------------

function Style.lighten(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), amount)
end

function Style.darken(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

-- Čitelný text na libovolném podkladu: na světlém tmavý, na tmavém bílý
function Style.contrast(background: Color3): Color3
	local luminance = background.R * 0.299 + background.G * 0.587 + background.B * 0.114
	return if luminance > 0.62 then Style.Palette.Ink else Style.Palette.Text
end

return Style

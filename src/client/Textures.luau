--!strict
--[[
	Textures — pohyb povrchů.

	Statická textura vypadá levně; pohybující se vypadá draze. Tenhle modul
	dělá čtyři věci, které v žánru vidíš pořád:

	  1. `scroll`  — posouvá texturu po povrchu (OffsetStudsU/V). Tohle je
	     ta klasická technika na tekoucí energii, běžící pás nebo lávu.
	  2. `energyField` — mřížka Beamů přes bariéru, která proudí nahoru.
	     Beam nepotřebuje žádný obrázek, takže tohle funguje i bez assetů.
	  3. `flowStripes` — pruhy na podlaze, které tečou k bariéře a ukazují,
	     kam běžet.
	  4. `charge` — bariéra pulzuje tím rychleji, čím blíž je proražení.
	     Hráč tak vidí svůj postup i bez koukání na UI.

	Všechno běží z jedné Heartbeat smyčky nad seznamem registrovaných
	efektů — desítky vlastních connectionů by se při přestavbě světa
	musely složitě uklízet.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Assets = require(Shared.Assets)
local Build = require(Shared.Build)
local Config = require(Shared.Config)

local Textures = {}

type Scroller = {
	Texture: Texture,
	SpeedU: number,
	SpeedV: number,
}

type Pulser = {
	Part: BasePart,
	Base: Color3,
	Peak: Color3,
	-- nil = tuhle bariéru teď neanimuj (barvu si řídí někdo jiný)
	Charge: () -> number?,
}

type Flow = {
	Parts: { BasePart },
	Origin: Vector3,
	Length: number,
	Speed: number,
	-- Ujetá vzdálenost; drží se zvlášť, aby změna tempa pruhy nepřeskočila
	Shift: number?,
}

local scrollers: { Scroller } = {}
local pulsers: { Pulser } = {}
local flows: { Flow } = {}
local elapsed = 0

--[[
	Intenzita — jak "rozjetá" trať je. 1 je klid, výš znamená rychlejší
	tok, jasnější pruhy a svižnější pulz. Řídí ji combo.

	Drží se zvlášť cílová a aktuální hodnota: skok na plný tok v jednom
	snímku vypadá jako závada, doběh za desetinu sekundy jako zrychlení.
]]
local intensity = 1
local intensityTarget = 1

--[[
	Záblesk. Krátký skok navrch intenzity, který sám odezní.

	Průraz zdi je jediná chvíle, kdy se ve hře opravdu něco stane —
	a do teď se to projevilo jen v místě nárazu. Světla haly to teď
	chytnou taky, takže rána prolétne celou místností.

	Drží se zvlášť od `intensity`, protože ta patří combu: kdyby záblesk
	přepsal cíl, spadl by po něm řetěz na klid, i když hráč pořád sbírá.
]]
local flash = 0

--[[
	Kolik z pruhu tvoří intenzita: při plném rozjetí je pruh skoro
	neprůhledný, v klidu skoro neviditelný. Bez toho by se zrychlení
	poznalo jen podle pohybu, který na malé obrazovce splyne.
]]
local STRIPE_ALPHA_CALM = 0.72
local STRIPE_ALPHA_HOT = 0.18

-- Posouvající se textura ---------------------------------------------------------

--[[
	Přidá texturu na jednu stranu dílu a rozpohybuje ji.
	Když v Assets žádné ID není, nevytvoří se nic — díl zůstane
	na svém materiálu a hra vypadá pořád dobře.
]]
function Textures.scroll(part: BasePart, face: Enum.NormalId, options: {
	Asset: string,
	Color: Color3,
	StudsPerTile: number,
	SpeedU: number?,
	SpeedV: number?,
	Transparency: number?,
}): Texture?
	if options.Asset == "" then
		return nil
	end

	local texture = Instance.new("Texture")
	texture.Texture = options.Asset
	texture.Face = face
	texture.Color3 = options.Color
	texture.Transparency = options.Transparency or 0.4
	texture.StudsPerTileU = options.StudsPerTile
	texture.StudsPerTileV = options.StudsPerTile
	texture.Parent = part

	table.insert(scrollers, {
		Texture = texture,
		SpeedU = options.SpeedU or 0,
		SpeedV = options.SpeedV or 0,
	})

	return texture
end

-- Energetické pole na bariéře -------------------------------------------------------

--[[
	Svislé Beamy přes celou bariéru. Beam bez textury je plný barevný pruh,
	takže tohle nepotřebuje jediný nahraný obrázek — a přesto se to hýbe:
	`TextureSpeed` posouvá gradient nahoru pořád dokola.
]]
function Textures.energyField(part: BasePart, world, count: number)
	local width = part.Size.X
	local height = part.Size.Y

	for index = 1, count do
		local offsetX = -width / 2 + width * (index - 0.5) / count

		local bottom = Instance.new("Attachment")
		bottom.Position = Vector3.new(offsetX, -height / 2, 0)
		bottom.Parent = part

		local top = Instance.new("Attachment")
		top.Position = Vector3.new(offsetX, height / 2, 0)
		top.Parent = part

		local beam = Instance.new("Beam")
		beam.Attachment0 = bottom
		beam.Attachment1 = top
		beam.Width0 = width / count * 0.55
		beam.Width1 = width / count * 0.55
		beam.FaceCamera = false
		beam.LightEmission = 0.9
		beam.LightInfluence = 0
		beam.Segments = 4
		beam.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, world.Accent),
			ColorSequenceKeypoint.new(0.5, world.Color),
			ColorSequenceKeypoint.new(1, world.Accent),
		})
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.85),
			NumberSequenceKeypoint.new(0.35, 0.35),
			NumberSequenceKeypoint.new(0.65, 0.35),
			NumberSequenceKeypoint.new(1, 0.85),
		})
		-- Rychlost se liší pruh od pruhu, aby pole nevypadalo jako mřížka
		beam.TextureSpeed = 1.4 + (index % 3) * 0.35
		beam.TextureLength = 6
		beam.Parent = part
	end
end

-- Pruhy na podlaze ------------------------------------------------------------------

--[[
	Světelné pruhy, které tečou po podlaze směrem k další bariéře.
	Kromě parády mají i funkci: ukazují, kam běžet.
]]
function Textures.flowStripes(parent: Instance, origin: Vector3, length: number, world, count: number, speed: number)
	local parts = table.create(count)

	for index = 1, count do
		parts[index] = Build.part({
			Name = "Stripe",
			Size = Vector3.new(Config.Track.Width - 10, 0.2, 5),
			--[[
				Nad dlaždicemi, ne v nich. Pruhy vznikly, když byla
				podlaha plochá deska; jakmile z ní byly vysoké kostky,
				zůstaly zahrabané uvnitř a nikdo je neviděl.
			]]
			Position = origin
				+ Vector3.new(0, Config.floorTop() + 0.2, length * (index - 1) / count),
			Color = world.Accent,
			Material = Enum.Material.Neon,
			Transparency = 0.6,
			CanCollide = false,
			CastShadow = false,
			Parent = parent,
		})
	end

	table.insert(flows, {
		Parts = parts,
		Origin = origin + Vector3.new(0, Config.floorTop() + 0.2, 0),
		Length = length,
		Speed = speed,
	})
end

-- Vznášející se rekvizity -------------------------------------------------------

--[[
	Rekvizity označené atributem `Float` se vznášejí a otáčejí.

	Staví je server, ale hýbe s nimi klient. Je to pohyb, který nikoho
	neovlivňuje — nikdo o něj nezakopne a nikdo z něj nic nezíská —
	takže by po síti chodit neměl. Server by ho posílal třicetkrát za
	sekundu všem hráčům jen proto, aby kostka nahoře udělala kolečko.

	Díly se hlásí samy přes `CollectionService`, ne prohledáváním
	`Workspace` každý snímek — a hlavně ne jednorázovým průchodem při
	stavbě světa.

	Ten průchod tu totiž byl a byl špatně: se zapnutým streamingem
	dorazí vzdálenější polovina trati k hráči až ve chvíli, kdy k ní
	dojde, takže ji sběr při stavbě NIKDY nenajde. Rekvizity za první
	třetinou trati se nerozhýbaly vůbec a poznat to šlo jen tím, že si
	toho někdo všimne. Značka naopak klientovi ohlásí každý díl přesně
	v okamžiku, kdy k němu dorazí.
]]
type Floater = {
	Part: BasePart,
	Base: CFrame,
	Speed: number,
	-- Vlastní fáze, aby všechny nešly nahoru a dolů zároveň
	Phase: number,
	World: string,
}

local floaters: { Floater } = {}
--[[
	Světy stojí 500 studů od sebe a streaming dosáhne 512, takže se
	sousední svět načte taky. Bez rozlišení by si klient animoval
	i jeho rekvizity — neviditelně, ale za práci v každém snímku.
]]
local floatWorld = ""

function Textures.setWorld(worldId: string)
	floatWorld = worldId
end

local function addFloater(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end

	local speed = instance:GetAttribute("Float")
	if typeof(speed) ~= "number" then
		return
	end

	for _, existing in floaters do
		if existing.Part == instance then
			return
		end
	end

	table.insert(floaters, {
		Part = instance,
		Base = instance.CFrame,
		Speed = speed,
		-- Fáze z pozice, ne z náhody: scéna pak vypadá na každém
		-- klientovi stejně a jde reprodukovat
		Phase = (instance.Position.X + instance.Position.Z) % (math.pi * 2),
		World = instance:GetAttribute("WorldId") or "",
	})
end

local function removeFloater(instance: Instance)
	for index, existing in floaters do
		if existing.Part == instance then
			table.remove(floaters, index)
			return
		end
	end
end

--[[
	Napojení na značku. Volá se jednou při startu klienta; od té chvíle
	se seznam plní i vyprazdňuje sám, jak se trať kolem hráče načítá
	a zase uvolňuje.
]]
function Textures.watchFloaters()
	for _, part in CollectionService:GetTagged("FloatProp") do
		addFloater(part)
	end

	CollectionService:GetInstanceAddedSignal("FloatProp"):Connect(addFloater)
	CollectionService:GetInstanceRemovedSignal("FloatProp"):Connect(removeFloater)
end

-- Zářivky v hale ---------------------------------------------------------------

--[[
	Světla haly, která hoří s combem.

	Zářivky, římsy a stropní panely jsou jediné velké plochy, které
	můžou na hraní reagovat. Když se hráči rozjede řetěz, rozsvítí se
	s ním celá místnost — a to je zpětná vazba, kterou vidí i ten, kdo
	se zrovna nedívá na kartu v rohu.

	Barvy si nese každý díl na sobě v atributech, protože je určuje
	svět a ten staví server. Klient by je jinak musel dopočítávat
	podruhé a druhý výpočet se dřív nebo později rozejde s prvním.
]]
type Glow = {
	Part: BasePart,
	Base: Color3,
	Peak: Color3,
	Light: PointLight?,
	Brightness: number,
	World: string,
}

local glows: { Glow } = {}

local function addGlow(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end

	local base = instance:GetAttribute("GlowBase")
	local peak = instance:GetAttribute("GlowPeak")
	if typeof(base) ~= "Color3" or typeof(peak) ~= "Color3" then
		return
	end

	for _, existing in glows do
		if existing.Part == instance then
			return
		end
	end

	local light = instance:FindFirstChildOfClass("PointLight")

	table.insert(glows, {
		Part = instance,
		Base = base,
		Peak = peak,
		Light = light,
		-- Původní jas se pamatuje: combo ho zvedá, klid ho musí vrátit
		Brightness = if light then light.Brightness else 0,
		World = instance:GetAttribute("WorldId") or "",
	})
end

local function removeGlow(instance: Instance)
	for index, existing in glows do
		if existing.Part == instance then
			table.remove(glows, index)
			return
		end
	end
end

function Textures.watchGlow()
	for _, part in CollectionService:GetTagged("WallGlow") do
		addGlow(part)
	end

	CollectionService:GetInstanceAddedSignal("WallGlow"):Connect(addGlow)
	CollectionService:GetInstanceRemovedSignal("WallGlow"):Connect(removeGlow)
end

-- Buněčná mřížka na povrchu ---------------------------------------------------

--[[
	Skutečná textura na tabuli — bez jediného nahraného obrázku.

	`SurfaceGui` přilepí 2D rozhraní na stěnu dílu, takže mřížka `Frame`
	prvků je z pohledu hráče normální textura. Oproti `Texture` s obrázkem
	má jednu zásadní výhodu: každá buňka je vlastní prvek, takže se dají
	rozsvěcet po jedné.

	Toho tady využíváme na to hlavní — nabití. Tabule se plní zdola
	nahoru jako sloupec kapaliny, takže hráč vidí svůj postup na zdi
	samotné a nemusí koukat do UI.

	Proč šachovnicově posunuté řady: pravidelná mřížka vypadá jako
	tabulka. Posun každé druhé řady o půl buňky z toho udělá vzor,
	který oko čte jako materiál.
]]
type Cell = {
	Frame: Frame,
	-- Podíl výšky, ve kterém buňka leží (0 dole, 1 nahoře)
	Level: number,
	-- Vlastní fáze, aby se buňky nerozsvěcely všechny naráz
	Phase: number,
}

type Grid = {
	Surface: SurfaceGui,
	Cells: { Cell },
	Base: Color3,
	Peak: Color3,
	Charge: () -> number?,
}

local grids: { Grid } = {}
--[[
	Mřížka je jediná vrstva, která má stovky prvků. Na slabém zařízení se
	proto celá vypne — `SurfaceGui.Enabled = false` je okamžité a nemusí
	se kvůli tomu přestavovat trať.
]]
local gridsEnabled = true

function Textures.cellGrid(part: BasePart, world, columns: number, rows: number, charge: () -> number?)
	local surface = Instance.new("SurfaceGui")
	surface.Name = "Mřížka"
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 24
	surface.LightInfluence = 0
	surface.AlwaysOnTop = false
	surface.Parent = part

	local cells: { Cell } = {}
	local cellWidth = 1 / columns
	local cellHeight = 1 / rows

	for row = 0, rows - 1 do
		-- Každá druhá řada posunutá o půl buňky
		local shift = if row % 2 == 1 then cellWidth / 2 else 0

		for column = 0, columns - 1 do
			local frame = Instance.new("Frame")
			frame.Size = UDim2.fromScale(cellWidth * 0.86, cellHeight * 0.86)
			frame.Position = UDim2.fromScale(
				column * cellWidth + shift + cellWidth * 0.07,
				(rows - 1 - row) * cellHeight + cellHeight * 0.07
			)
			frame.BackgroundColor3 = world.Color
			frame.BackgroundTransparency = 0.9
			frame.BorderSizePixel = 0
			frame.Parent = surface

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.18, 0)
			corner.Parent = frame

			table.insert(cells, {
				Frame = frame,
				Level = row / math.max(rows - 1, 1),
				Phase = (row * 0.7 + column * 1.3) % (math.pi * 2),
			})
		end
	end

	surface.Enabled = gridsEnabled

	table.insert(grids, {
		Surface = surface,
		Cells = cells,
		Base = world.Color,
		Peak = world.Accent,
		Charge = charge,
	})
end

-- Pulzování podle nabití --------------------------------------------------------------

--[[
	Bariéra dýchá tím rychleji, čím blíž je proražení.

	`charge` je funkce, ne číslo — nabití se mění každý snímek. Když vrátí
	nil, modul se barvy nedotkne: zamčené a proražené bariéry si barvu
	řídí samy a pulz by jim ji přepisoval.
]]
function Textures.charge(part: BasePart, base: Color3, peak: Color3, charge: () -> number?)
	table.insert(pulsers, {
		Part = part,
		Base = base,
		Peak = peak,
		Charge = charge,
	})
end

-- Úklid a smyčka -------------------------------------------------------------------

-- Při přestavbě světa se díly zničí; osiřelé záznamy odsud vypadnou samy.
local function prune()
	for index = #scrollers, 1, -1 do
		if not scrollers[index].Texture.Parent then
			table.remove(scrollers, index)
		end
	end
	for index = #pulsers, 1, -1 do
		if not pulsers[index].Part.Parent then
			table.remove(pulsers, index)
		end
	end
	for index = #glows, 1, -1 do
		if not glows[index].Part.Parent then
			table.remove(glows, index)
		end
	end
	for index = #flows, 1, -1 do
		if not flows[index].Parts[1].Parent then
			table.remove(flows, index)
		end
	end
	for index = #grids, 1, -1 do
		if not grids[index].Surface.Parent then
			table.remove(grids, index)
		end
	end
end

--[[
	Nastaví, jak rozjetá trať má být. 1 = klid.

	Volá se při změně stupně comba, ne při každém pickupu — přepočítávat
	tok padesátkrát za vteřinu by nic nepřidalo a jen by to blikalo.
]]
function Textures.setLowGraphics(enabled: boolean)
	gridsEnabled = not enabled

	for _, grid in grids do
		grid.Surface.Enabled = gridsEnabled
	end
end

function Textures.setIntensity(value: number)
	intensityTarget = math.clamp(value, 1, 3)
end

--[[
	`strength` je 0..1; větší přeplácnutí zdi znamená větší ránu.
	Sčítá se, ne přepisuje — dva průrazy hned po sobě mají svítit víc
	než jeden.
]]
function Textures.flash(strength: number)
	flash = math.min(flash + math.clamp(strength, 0, 1) * 1.4, 2.2)
end

function Textures.reset()
	table.clear(scrollers)
	table.clear(pulsers)
	table.clear(flows)
	table.clear(grids)
	flash = 0
	--[[
		Vznášející se rekvizity ani zářivky se tady schválně NEmažou.
		Oba seznamy si drží značka a plní se, jak se trať kolem hráče
		načítá; kdyby je přestavba světa vysypala, doplnily by se jen
		o díly, které se mezitím znovu načetly — tedy skoro o nic.
		Který svět je ten současný, řeší `setWorld`.
	]]
	intensity = 1
	intensityTarget = 1
end

function Textures.start()
	local sincePrune = 0

	Textures.watchFloaters()
	Textures.watchGlow()

	RunService.Heartbeat:Connect(function(deltaTime)
		elapsed += deltaTime
		sincePrune += deltaTime

		-- Exponenciální doběh: nezávisí na snímkové frekvenci, takže
		-- na 30 i 144 FPS trvá zrychlení stejně dlouho.
		intensity += (intensityTarget - intensity) * math.min(deltaTime * 6, 1)

		-- Doběh záblesku: rychlejší než náběh comba, aby rána byla rána
		flash = math.max(flash - flash * math.min(deltaTime * 3.2, 1) - deltaTime * 0.2, 0)

		for _, scroller in scrollers do
			local texture = scroller.Texture
			if scroller.SpeedU ~= 0 then
				texture.OffsetStudsU = (texture.OffsetStudsU + scroller.SpeedU * intensity * deltaTime) % texture.StudsPerTileU
			end
			if scroller.SpeedV ~= 0 then
				texture.OffsetStudsV = (texture.OffsetStudsV + scroller.SpeedV * intensity * deltaTime) % texture.StudsPerTileV
			end
		end

		--[[
			Zářivky. Sytost se řídí intenzitou (tedy combem) a k tomu
			pomalu dýchají — nehybné světlo na velké ploše vypadá jako
			nakreslené, dýchající jako rozsvícené.

			Fáze se odvozuje z pozice dílu, takže sousední zářivky
			nedýchají zároveň a hala nebliká jako jedna žárovka.
		]]
		local heat = math.clamp(intensity - 1 + flash, 0, 1)

		for _, glow in glows do
			if glow.World ~= "" and glow.World ~= floatWorld then
				continue
			end

			local part = glow.Part
			local phase = (part.Position.Z + part.Position.X) * 0.04
			local breath = (math.sin(elapsed * 1.6 + phase) + 1) / 2

			part.Color = glow.Base:Lerp(glow.Peak, heat * 0.7 + breath * 0.12)
			part.Transparency = 0.16 - heat * 0.1

			local light = glow.Light
			if light then
				light.Brightness = glow.Brightness * (1 + heat * 1.2 + breath * 0.15)
			end
		end

		for _, pulser in pulsers do
			local charge = pulser.Charge()
			if charge then
				local wave = (math.sin(elapsed * (3 + charge * 14) * intensity) + 1) / 2
				pulser.Part.Color = pulser.Base:Lerp(pulser.Peak, wave * 0.75)
			end
		end

		-- Pruhy tečou dopředu a na konci trati se vrátí na začátek.
		-- Modulo drží pozici v rozsahu tratě bez dopočítávání stavu.
		--[[
			Pruhy: pozice se počítá z `flow.Shift`, ne z `elapsed * Speed`.
			Kdyby se násobilo přímo uplynulým časem, změna intenzity by
			pruhy skokem přemístila — takhle se jen změní tempo posunu.
		]]
		local alpha = STRIPE_ALPHA_CALM
			+ (STRIPE_ALPHA_HOT - STRIPE_ALPHA_CALM) * math.clamp(intensity - 1, 0, 1)

		for _, flow in flows do
			local count = #flow.Parts
			local spacing = flow.Length / count
			flow.Shift = ((flow.Shift or 0) + flow.Speed * intensity * deltaTime) % spacing

			for index, part in flow.Parts do
				local base = spacing * (index - 1) + flow.Shift
				part.Position = flow.Origin + Vector3.new(0, 0, base % flow.Length)
				part.Transparency = alpha
			end
		end

		--[[
			Mřížka se plní zdola. Buňka pod hladinou svítí, nad hladinou
			je skoro průhledná; přechod je měkký, aby hladina nebyla
			ostrá čára. Nad plným nabitím celá tabule dýchá.
		]]
		for _, grid in grids do
			local charge = if gridsEnabled then grid.Charge() else nil
			if not charge then
				continue
			end

			for _, cell in grid.Cells do
				-- Vzdálenost buňky od hladiny; kladná = pod ní
				local depth = charge - cell.Level
				local lit = math.clamp(depth * 6 + 0.5, 0, 1)

				local shimmer = 0
				if charge >= 1 then
					shimmer = (math.sin(elapsed * 6 * intensity + cell.Phase) + 1) / 2 * 0.35
				end

				cell.Frame.BackgroundTransparency = 0.9 - (lit * 0.75 + shimmer * 0.15)
				cell.Frame.BackgroundColor3 = grid.Base:Lerp(grid.Peak, math.min(lit + shimmer, 1))
			end
		end

		--[[
			Vznášení. Otáčí se kolem svislé osy a zároveň se houpe nahoru
			a dolů; obojí z jedné základní polohy, takže se to nikdy
			nerozejde ani po hodinách běhu.
		]]
		for _, floater in floaters do
			local part = floater.Part
			if not part.Parent or floater.World ~= floatWorld then
				continue
			end

			local time = elapsed * floater.Speed + floater.Phase
			part.CFrame = floater.Base
				* CFrame.new(0, math.sin(time) * 1.6, 0)
				* CFrame.Angles(0, time * 0.5, 0)
		end

		if sincePrune >= 2 then
			sincePrune = 0
			prune()
		end
	end)
end

-- Textura z Assets podle role ("Barrier" / "Floor" / "Wall")
function Textures.assetFor(role: string): string
	return Assets.Textures[role] or ""
end

return Textures

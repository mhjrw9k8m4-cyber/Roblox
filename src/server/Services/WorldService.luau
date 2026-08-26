--!strict
--[[
	WorldService — postaví tratě všech světů z kódu.

	Staví se jen to, co je pro všechny stejné: podlaha, stěny, rámy dveří,
	startovní a cílová plošina. Samotné prorazitelné tabule a pickupy staví
	klient lokálně — musí totiž blokovat a mizet každému hráči zvlášť podle
	jeho vlastního postupu, což sdílená geometrie neumí.
]]

local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Build = require(Shared.Build)
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Props = require(Shared.Props)
local Live = require(Shared.Live)
local Track = require(Shared.Track)
local Toy = require(Shared.Toy)
local Zones = require(Shared.Zones)

local WorldService = {}

local TRACK = Config.Track

--[[
	Osvětlení ve stylu, ve kterém jsou dělané populární Roblox hry:
	**jasné, syté a bez oparu**.

	Předchozí verze byla temná a zamlžená — vypadalo to "filmově", ale
	právě to je v tomhle žánru špatně. Hráč má vidět celou chodbu naráz,
	barvy mají svítit a nic se nemá ztrácet ve stínu. Šero a mlha jsou
	nástroje hororu, ne barevného simulátoru.

	Konkrétně: vyšší jas, světlejší ambient (žádné černé stíny), mlha až
	daleko a jen slabý opar.
]]
local function buildLighting()
	Lighting.Ambient = Color3.fromRGB(126, 118, 148)
	Lighting.OutdoorAmbient = Color3.fromRGB(146, 138, 168)
	Lighting.Brightness = 3
	Lighting.ClockTime = 14
	Lighting.EnvironmentDiffuseScale = 0.7
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.GlobalShadows = true

	for _, className in { "Atmosphere", "BloomEffect", "ColorCorrectionEffect" } do
		local existing = Lighting:FindFirstChildOfClass(className)
		if existing then
			existing:Destroy()
		end
	end

	local atmosphere = Instance.new("Atmosphere")
	-- Skoro nic: opar má barvám dát hloubku, ne je zašedit
	atmosphere.Density = 0.08
	atmosphere.Haze = 0.4
	atmosphere.Glare = 0.1
	atmosphere.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	-- Bloom zůstává silný: rozzářené neony jsou v žánru podpis
	bloom.Intensity = 1.3
	bloom.Size = 24
	bloom.Threshold = 0.9
	bloom.Parent = Lighting

	local color = Instance.new("ColorCorrectionEffect")
	-- Víc barvy, míň kontrastu: sytě a čitelně, ne "filmově"
	color.Saturation = 0.35
	color.Contrast = 0.05
	color.Brightness = 0.02
	color.Parent = Lighting

	--[[
		Obloha bez jediné textury.

		`Sky` s prázdnými `SkyboxUp/Dn/...` vykreslí jednolitou plochu —
		tu ale nechceme vidět, protože mlha končí dřív. Co z oblohy
		zbývá vidět, jsou hvězdy a slunce, a ty stačí naladit: hustá
		hvězdná obloha za mlhou vypadá jako hloubka, ne jako stěna.

		Barvu oblohy pak přebarví mlha podle světa (viz klient), takže
		tady se řeší jen struktura.
	]]
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky then
		sky:Destroy()
	end

	sky = Instance.new("Sky")
	sky.StarCount = 3000
	sky.SunAngularSize = 12
	sky.MoonAngularSize = 0
	sky.CelestialBodiesShown = true
	sky.Parent = Lighting

	--[[
		Sluneční paprsky. Nejlevnější efekt, který dá scéně objem —
		světlo se opře do oblouků a chodba dostane hloubku.
	]]
	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if rays then
		rays:Destroy()
	end

	rays = Instance.new("SunRaysEffect")
	-- Jen naznačit; silné paprsky ve vnitřní chodbě vypadají jako závada
	rays.Intensity = 0.06
	rays.Spread = 0.5
	rays.Parent = Lighting

	--[[
		Hloubka ostrosti se NEPOUŽÍVÁ.

		Byla tam a je pryč. Rozostřená dálka je filmový efekt a v Roblox
		simulátoru působí jako rozmazaná grafika — hráč má vidět ostře
		celou chodbu včetně zdi na konci. Populární hry v žánru ji nemají
		ani jedna.

		Zbylá po předchozí verzi se maže, ne jen vypíná: vypnutý efekt
		by se dal omylem zapnout a nikdo by nevěděl proč.
	]]
	local depth = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if depth then
		depth:Destroy()
	end
end

--[[
	Startovní plošina se jménem světa. Zároveň je to místo, kam se hráč
	teleportuje při vstupu do světa i po resetu postavy.
]]
--[[
	Startovní plac.

	Byla to holá zářící plošina s cedulí. Přitom je to **první, co hráč
	po spuštění vidí**, a v žánru je to obvykle nejzdobenější místo
	celé mapy — hráč se tam vrací po každém kole a stráví tam čas
	v obchodě.

	Stojí tu tři věci, každá z jiného důvodu:
	  * portál nad startem  — rámuje výběh a je vidět z celé trati
	  * tabule po stranách  — kam se dá dokreslit žebříček a nabídky
	  * sloupky s lany      — ohraničí plac, aby nebyl jen kus podlahy
]]
--[[
	Co se píše na tabule u startu.

	Pravidla jsou napsaná, ne odvozená: je to text pro člověka, ne
	konfigurace. Kolotoč odměn se naopak skládá z `Live.Daily`, takže
	když se odměny změní, tabule se změní s nimi — opsaná čísla by se
	rozešla a hráč by u tabule čekal na něco, co nepřijde.
]]
local HOW_TO_PLAY = {
	"1  ·  Walk over the +1 cubes",
	"2  ·  Run into the wall to SMASH",
	"3  ·  Spend coins on upgrades",
	"4  ·  Squeeze the squishy for free power",
}

local function dailyLines(): { string }
	local lines = {}

	for _, day in Live.Daily do
		local reward = `+{day.Gems} 💎`
		if day.Squishy then
			local squishy = Live.squishy(day.Squishy)
			reward ..= `  +  {if squishy then squishy.Name else day.Squishy}`
		end
		table.insert(lines, `DAY {day.Day}   {reward}`)
	end

	return lines
end

--[[
	Text na plochu tabule.

	SurfaceGui, ne billboard: nápis má na tabuli ležet, ne se otáčet za
	hráčem. Billboard nad tabulí, který se hýbe, čte oko jako UI; text
	na desce jako ceduli, která tam stojí.
]]
local function boardText(face: BasePart, lines: { string })
	local surface = Instance.new("SurfaceGui")
	surface.Name = "Text tabule"
	surface.Face = Enum.NormalId.Back
	surface.CanvasSize = Vector2.new(340, 300)
	surface.LightInfluence = 0
	surface.Adornee = face
	surface.Parent = face

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = surface

	for index, text in lines do
		local label = Instance.new("TextLabel")
		label.Name = `Řádek {index}`
		label.Size = UDim2.new(1, -20, 0, math.floor(260 / #lines))
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.Text = text
		label.TextColor3 = Config.Theme.Text
		label.TextScaled = true
		label.LayoutOrder = index
		label.Parent = surface

		local stroke = Instance.new("UIStroke")
		stroke.Color = Config.Theme.Outline
		stroke.Thickness = 3
		stroke.Parent = label
	end
end

--[[
	Označí díl, který si má klient animovat.

	Značka, ne jen atribut. Se zapnutým streamingem dorazí vzdálenější
	polovina trati k hráči až ve chvíli, kdy k ní dojde — jednorázový
	průchod stromem při stavbě světa ji tedy nikdy nenajde a ty díly se
	nerozhýbou vůbec. `CollectionService` naopak klientovi ohlásí každý
	díl v okamžiku, kdy k němu dorazí.

	`WorldId` je tam proto, že světy stojí 500 studů od sebe a streaming
	dosáhne 512 — sousední svět se tedy načte taky a bez rozlišení by si
	klient animoval i jeho rekvizity.
]]
local function markFloater(part: BasePart, speed: number, worldId: string)
	part:SetAttribute("Float", speed)
	part:SetAttribute("WorldId", worldId)
	CollectionService:AddTag(part, "FloatProp")
end

--[[
	Truhla na placu.

	Odpočet volné truhly byl jen číslo v rohu HUD. Číslo v rohu se dá
	přehlédnout a hráč, který o volné odměně neví, si ji nevezme —
	odměna, kterou si nikdo nevezme, je stejná jako žádná.

	Truhla stojí u startu proto, že tam se hráč vrací sám od sebe po
	každém kole. Nemusí se kvůli ní nikam odbočovat: uvidí ji cestou
	a pozná na ní, jestli má, nebo kolik zbývá.

	Stojí ve všech světech, ne jen v prvním — hráč, který se přestěhoval
	do šestého světa, by pro ni jinak musel běhat zpátky.
]]
local function buildChest(world, parent: Instance, origin: Vector3)
	--[[
		U levého kraje placu, ne uprostřed: uprostřed vede běžecká
		stopa ze startu na trať a hráč by truhlu vybíral pokaždé, když
		kolem ní proběhne.
	]]
	local spot = origin + Vector3.new(-(TRACK.Width / 2 - 8), 0, -30)

	local body = Build.part({
		Name = "Truhla",
		Size = Vector3.new(8, 5, 6),
		Position = spot + Vector3.new(0, 4.5, 0),
		Color = Config.Theme.Gold,
		Material = Enum.Material.Plastic,
		Surface = Enum.SurfaceType.Studs,
		CanCollide = false,
		Parent = parent,
	})
	CollectionService:AddTag(body, "ChestPad")

	Build.part({
		Name = "Víko truhly",
		Size = Vector3.new(8.6, 1.8, 6.6),
		Position = spot + Vector3.new(0, 7.8, 0),
		Color = Config.Theme.Panel,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = parent,
	})

	--[[
		Světelný pás pod truhlou. Klient ho přebarvuje podle toho, jestli
		je odměna k vyzvednutí — je to jediná část truhly, která je vidět
		i z druhého konce placu.
	]]
	local glow = Build.part({
		Name = "Světlo truhly",
		Size = Vector3.new(9.4, 0.6, 7.4),
		Position = spot + Vector3.new(0, 2.2, 0),
		Color = world.Accent,
		Material = Enum.Material.Neon,
		Transparency = 0.2,
		CanCollide = false,
		CastShadow = false,
		Parent = parent,
	})
	Build.light(glow, Config.Theme.Gold, 2.4, 30)

	--[[
		Text doplňuje klient: odpočet i to, jestli je truhla připravená,
		se liší hráč od hráče.
	]]
	local _, label = Build.billboard({
		Adornee = body,
		Text = "<b>🎁 FREE CHEST</b>",
		Size = UDim2.fromScale(16, 5),
		Offset = Vector3.new(0, 6, 0),
		Color = Config.Theme.Gold,
		MaxDistance = 260,
	})
	label.Name = "ChestText"
end

local function buildStart(world, worldIndex: number, parent: Instance)
	local origin = Track.origin(worldIndex)

	local pad = Build.part({
		Name = "Start",
		Size = Vector3.new(TRACK.Width, 2, 44),
		Position = origin + Vector3.new(0, 1, -24),
		Color = world.Accent,
		Material = Enum.Material.Neon,
		Transparency = 0.25,
		Parent = parent,
	})
	Build.light(pad, world.Accent, 3, 40)

	--[[
		Portál nad výběhem. Dva sloupy a překlad — jednoduchý tvar, ale
		z celé trati je vidět, kde trať začíná, a při návratu na start
		je zřejmé, kam běžet.
	]]
	for _, side in { -1, 1 } do
		local column = Build.part({
			Name = "Portál",
			Size = Vector3.new(4, 34, 4),
			Position = origin + Vector3.new(side * (TRACK.Width / 2 + 2), 17, -4),
			Color = Config.Theme.Panel,
			Material = Enum.Material.Plastic,
			-- Sloup z kostek, ne z hladkého plastu: brána u startu je
			-- první věc, kterou hráč po naběhnutí uvidí
			Surface = Enum.SurfaceType.Studs,
			CanCollide = false,
			Parent = parent,
		})

		local strip = Build.part({
			Name = "Světlo portálu",
			Size = Vector3.new(1.2, 28, 1.2),
			Position = origin + Vector3.new(side * (TRACK.Width / 2 - 0.4), 17, -4),
			Color = world.Accent,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
			Parent = parent,
		})
		Build.light(strip, world.Accent, 2.4, 28)
		column.Reflectance = 0.15
	end

	local lintel = Build.part({
		Name = "Překlad startu",
		Size = Vector3.new(TRACK.Width + 12, 6, 5),
		Position = origin + Vector3.new(0, 36, -4),
		Color = Config.Theme.Panel,
		Material = Enum.Material.Plastic,
		Surface = Enum.SurfaceType.Studs,
		CanCollide = false,
		Parent = parent,
	})

	Build.billboard({
		Adornee = lintel,
		Text = `<b>{string.upper(world.Name)}</b>`,
		Size = UDim2.fromScale(34, 7),
		Offset = Vector3.new(0, 1, -3),
		Color = world.Color,
		MaxDistance = 700,
	})

	--[[
		Tabule po stranách placu.

		Stojí na `z = -46`, ne u kraje placu. Tam totiž **už jedna tabule
		je** — skutečný žebříček, který staví `LeaderboardService` u spawnu
		prvního světa na `(-26, -26)`. Kdyby se sem daly dekorativní, prošly
		by jedna druhou.

		Dřív na nich byl jen nadpis. Jedna z nich se navíc jmenovala
		"TOP SMASHERS" a stála dvacet studů od skutečného žebříčku, takže
		vedle sebe byly dvě tabule s tím samým slibem — jedna živá,
		druhá prázdná. To je přesně ten detail, po kterém hra vypadá
		jako rozestavěná.

		Obě teď nesou skutečný obsah, který si server skládá z dat:
		pravidla hry a sedmidenní kolotoč odměn.
	]]
	local BOARDS = {
		{ Side = -1, Title = "HOW TO PLAY", Color = Config.Theme.Acid, Lines = HOW_TO_PLAY },
		{ Side = 1, Title = "DAILY REWARD", Color = Config.Theme.Violet, Lines = dailyLines() },
	}

	for _, board in BOARDS do
		local frame = Build.part({
			Name = "Plakát",
			Size = Vector3.new(20, 18, 2),
			CFrame = CFrame.new(origin + Vector3.new(board.Side * 26, 11, -46))
				* CFrame.Angles(0, math.rad(-board.Side * 24), 0),
			Color = Config.Theme.PanelDeep,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			Parent = parent,
		})

		local face = Build.part({
			Name = "Plocha plakátu",
			Size = Vector3.new(17, 15, 0.6),
			CFrame = frame.CFrame * CFrame.new(0, 0, -1.2),
			Color = board.Color,
			Material = Enum.Material.Neon,
			Transparency = 0.25,
			CanCollide = false,
			CastShadow = false,
			Parent = parent,
		})
		Build.light(face, board.Color, 1.6, 24)

		Build.billboard({
			Adornee = frame,
			Text = `<b>{board.Title}</b>`,
			Size = UDim2.fromScale(18, 4),
			Offset = Vector3.new(0, 10, 0),
			Color = board.Color,
			MaxDistance = 260,
		})

		boardText(face, board.Lines)
	end

	--[[
		Sloupky s lany kolem placu. Ohraničí ho, takže start vypadá jako
		místo, ne jako kus podlahy, která náhodou svítí.
	]]
	for index = 0, 5 do
		for _, side in { -1, 1 } do
			--[[
				Sloupky začínají až za plakáty. Ty stojí na `z = -46` a jsou
				dvacet studů široké, takže první sloupek by v nich vězel.
			]]
			local z = -38 + index * 8

			local post = Build.part({
				Name = "Sloupek",
				Size = Vector3.new(1.2, 5, 1.2),
				Position = origin + Vector3.new(side * (TRACK.Width / 2 - 1), 2.5, z),
				Color = Config.Theme.PanelDeep,
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
				Parent = parent,
			})
			post.Reflectance = 0.2

			-- Lano jen mezi sloupky, ne za posledním
			if index < 5 then
				Build.part({
					Name = "Lano",
					Size = Vector3.new(0.4, 0.4, 8),
					Position = origin + Vector3.new(side * (TRACK.Width / 2 - 1), 4.2, z + 4),
					Color = world.Accent,
					Material = Enum.Material.Neon,
					Transparency = 0.2,
					CanCollide = false,
					CastShadow = false,
					Parent = parent,
				})
			end
		end
	end

	buildChest(world, parent, origin)
end

-- Cílová plošina za poslední bariérou
--[[
	Cíl trati.

	Byla to zelená plocha s cedulí. Přitom je to místo, kam hráč doběhne
	po dvanácti zdech — a odměna má být vidět dřív, než tam dojde.

	Stojí tu brána přes celou šířku, dva sloupy světla vzhůru a řada
	praporků. Světelné sloupy jsou tam schválně: jsou vidět **přes zdi**,
	takže hráč od začátku trati ví, kam běží.
]]
local function buildFinish(world, worldIndex: number, parent: Instance)
	local position = Track.finishPosition(worldIndex)

	local pad = Build.part({
		Name = "Finish",
		Size = Vector3.new(TRACK.Width, 2, 40),
		Position = position + Vector3.new(0, -3, 0),
		Color = Config.Theme.Success,
		Material = Enum.Material.Neon,
		Transparency = 0.2,
		Parent = parent,
	})
	Build.light(pad, Config.Theme.Success, 4, 50)

	-- Brána: dva sloupy a překlad přes celou chodbu
	for _, side in { -1, 1 } do
		local column = Build.part({
			Name = "Sloup cíle",
			Size = Vector3.new(5, 40, 5),
			Position = position + Vector3.new(side * (TRACK.Width / 2 + 2), 20, 0),
			Color = Config.Theme.Panel,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			Parent = parent,
		})
		column.Reflectance = 0.2

		local strip = Build.part({
			Name = "Světlo cíle",
			Size = Vector3.new(1.4, 34, 1.4),
			Position = position + Vector3.new(side * (TRACK.Width / 2 - 0.6), 20, 0),
			Color = Config.Theme.Success,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
			Parent = parent,
		})
		Build.light(strip, Config.Theme.Success, 3, 34)

		--[[
			Sloup světla vzhůru. Je vidět přes zdi, takže hráč od startu
			ví, kam běží — a cíl tím přestává být překvapení na konci
			a stává se z něj směr.

			Výška se počítá z haly, ne pevným číslem. Dřív byl sloup
			sto šedesát studů vysoký a začínal dvacet studů nad zemí:
			to dávalo smysl v otevřené chodbě, ale hala má strop
			v sedmdesáti dvou, takže dvě třetiny majáku trčely NAD
			stropem, kde je hráč neuvidí, a dole u země, kde se hráč
			dívá, nezačínal vůbec. Pošesté ta samá chyba: terén se
			posunul a to, co na něm stálo, ne.
		]]
		local beamHeight = TRACK.HallHeight - 8
		local beam = Build.part({
			Name = "Maják cíle",
			Size = Vector3.new(3, beamHeight, 3),
			Position = position + Vector3.new(side * (TRACK.Width / 2 + 2), beamHeight / 2, 0),
			Color = Config.Theme.Success,
			Material = Enum.Material.Neon,
			Transparency = 0.82,
			CanCollide = false,
			CastShadow = false,
			Parent = parent,
		})
		markFloater(beam, 0.2, world.Id)
	end

	local lintel = Build.part({
		Name = "Překlad cíle",
		Size = Vector3.new(TRACK.Width + 14, 7, 6),
		Position = position + Vector3.new(0, 41, 0),
		Color = Config.Theme.Panel,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = parent,
	})

	Build.billboard({
		Adornee = lintel,
		Text = "<b>WORLD CLEARED!</b>",
		Size = UDim2.fromScale(36, 8),
		Offset = Vector3.new(0, 1, 0),
		Color = Config.Theme.Success,
		MaxDistance = 900,
	})

	--[[
		Praporky napříč bránou. Střídají dvě barvy, takže i statická řada
		vypadá jako pohyb — je to nejlevnější způsob, jak dát cíli
		"závodní" ráz.
	]]
	for index = 0, 10 do
		local x = -TRACK.Width / 2 + index * (TRACK.Width / 10)

		Build.part({
			Name = "Praporek",
			Size = Vector3.new(3, 4, 0.3),
			CFrame = CFrame.new(position + Vector3.new(x, 34, 0))
				* CFrame.Angles(0, 0, math.rad(if index % 2 == 0 then 12 else -12)),
			Color = if index % 2 == 0 then Config.Theme.Success else world.Accent,
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0.1,
			CanCollide = false,
			CastShadow = false,
			Parent = parent,
		})
	end
end

local function buildBarrierFrame(world, worldIndex: number, index: number, parent: Instance)
	local center = Track.barrierPosition(worldIndex, index)

	for _, side in { -1, 1 } do
		local pillar = Build.part({
			Name = "Sloupek",
			Size = Vector3.new(3, 22, 3),
			Position = center + Vector3.new(side * (TRACK.Width / 2 - 1.5), 5, 0),
			Color = Config.Theme.PanelLight,
			Material = Enum.Material.Metal,
			Parent = parent,
		})

		local lamp = Build.part({
			Name = "Světlo",
			Size = Vector3.new(2, 1.4, 2),
			Position = center + Vector3.new(side * (TRACK.Width / 2 - 1.5), 16, 0),
			Color = world.Accent,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
			Parent = parent,
		})
		Build.light(lamp, world.Accent, 2.5, 30)
		pillar.CastShadow = false
	end

	Build.part({
		Name = "Překlad",
		Size = Vector3.new(TRACK.Width, 3, 3),
		Position = center + Vector3.new(0, 17.5, 0),
		Color = Config.Theme.PanelLight,
		Material = Enum.Material.Metal,
		CastShadow = false,
		Parent = parent,
	})
end

--[[
	Architektura tratě.

	Chodba z podlahy a dvou zdí je technicky správně a vypadá jako krabice.
	Rozdíl mezi „prototyp" a „hra" dělá to, že prostor má **rytmus** —
	něco, co se opakuje a čím kolem tebe ubíhá, takže je vidět rychlost.

	Tři vrstvy, každá v jiné vzdálenosti:
	  * oblouky u každé zdi   — rámují cíl, na který běžíš
	  * sloupy mezi zdmi      — rytmus přímo vedle tebe
	  * plovoucí kry v dálce  — hloubka za stěnami

	Všechno je ukotvené, bez kolizí a bez dotazů, takže to nic nestojí
	kromě vykreslení. Stín vrhají jen sloupy — u průsvitných ker by byl
	stín jen šum.
]]

-- Oblouk nad každou bariérou. Nese barvu světa a zvedá strop, takže
-- chodba nepůsobí jako tunel s víkem.
local function buildArch(world, origin: Vector3, z: number, parent: Instance)
	local half = TRACK.Width / 2 + 2

	for _, side in { -1, 1 } do
		Build.part({
			Name = "Sloup oblouku",
			Size = Vector3.new(2.4, 30, 2.4),
			Position = origin + Vector3.new(side * half, 15, z),
			Color = Config.Theme.Background,
			Material = Enum.Material.Concrete,
			CanCollide = false,
			Parent = parent,
		})

		local glow = Build.part({
			Name = "Svit oblouku",
			Size = Vector3.new(0.8, 26, 0.8),
			Position = origin + Vector3.new(side * (half - 1.4), 15, z),
			Color = world.Accent,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
			Parent = parent,
		})
		glow.Transparency = 0.1
		Build.light(glow, world.Accent, 1.6, 26)
	end

	-- Překlad. Mírně nad zdí, aby přes něj šlo vidět rozpad tabule.
	Build.part({
		Name = "Překlad oblouku",
		Size = Vector3.new(TRACK.Width + 8, 3.2, 3),
		Position = origin + Vector3.new(0, 30, z),
		Color = Config.Theme.Background,
		Material = Enum.Material.Concrete,
		CanCollide = false,
		Parent = parent,
	})

	local bar = Build.part({
		Name = "Světlo překladu",
		Size = Vector3.new(TRACK.Width + 2, 0.7, 1.2),
		Position = origin + Vector3.new(0, 28.2, z),
		Color = world.Color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
		Parent = parent,
	})
	bar.Transparency = 0.05
end

--[[
	Sloupy mezi bariérami. Tohle je ta vrstva, kterou hráč při běhu vnímá
	nejvíc — míjí je nejblíž, takže dělají pocit rychlosti.
]]
local function buildPillars(world, origin: Vector3, z: number, parent: Instance)
	local half = TRACK.Width / 2 - 1.2

	for _, side in { -1, 1 } do
		local pillar = Build.part({
			Name = "Sloup",
			Size = Vector3.new(1.8, 12, 1.8),
			Position = origin + Vector3.new(side * half, 6, z),
			Color = world.Color,
			Material = world.Material,
			CanCollide = false,
			Parent = parent,
		})
		pillar.Transparency = 0.35
		pillar.Reflectance = 0.3

		local cap = Build.part({
			Name = "Hlavice",
			Size = Vector3.new(2.6, 1.4, 2.6),
			Position = origin + Vector3.new(side * half, 12.6, z),
			Color = world.Accent,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
			Shape = Enum.PartType.Ball,
			Parent = parent,
		})
		-- Bez PointLightu schválně: Neon svítí sám a světel je v chodbě
		-- už tak dost. Světla jsou to nejdražší, co se dá do světa dát.
		cap.Transparency = 0.1
	end
end

--[[
	Plovoucí kry NAD chodbou. Hloubka pozadí za pár dílů — bez nich končí
	svět tři metry od hráče a je to znát.

	Dvakrát skončily tam, kam nebylo vidět: nejdřív za neprůhlednými
	stěnami, pak nad stropem chodby. Teď se vznášejí uvnitř haly, mezi
	dráhou a vzdálenou stěnou, kde jsou přes nízké zábradlí vidět
	z celé trati.

	Velikosti a natočení se odvozují z indexu, ne z náhody: svět tak
	vypadá na každém serveru stejně a jde ho reprodukovat.
]]
local function buildDrift(world, origin: Vector3, length: number, parent: Instance)
	local count = 26

	for index = 1, count do
		local t = index / count
		local side = if index % 2 == 0 then 1 else -1
		--[[
			Nejvzdálenější kra musí zůstat před stěnou haly, ne za ní.
			Rozestup se proto počítá z volného místa mezi dráhou
			a stěnou, ne pevným číslem — jinak by se při každé změně
			šířky haly zase pár kusů propadlo ven.
		]]
		local room = TRACK.HallWidth / 2 - TRACK.Width / 2
		local distance = TRACK.Width / 2 + room * (0.2 + (index % 5) * 0.15)
		local height = 14 + (index % 7) * 6
		local size = 5 + (index % 4) * 4

		local shard = Build.part({
			Name = "Kra",
			Size = Vector3.new(size, size * 1.6, size),
			CFrame = CFrame.new(origin + Vector3.new(side * distance, height, length * t))
				* CFrame.Angles(index * 0.4, index * 0.7, index * 0.23),
			Color = world.Color,
			Material = world.Material,
			CanCollide = false,
			CastShadow = false,
			Parent = parent,
		})
		shard.Transparency = 0.55
		shard.Reflectance = 0.35
	end
end

--[[
	Cedule na začátku zóny.

	Bez ní by se terén změnil "jen tak" a hráč by nevěděl, že něčeho
	dosáhl. S ní je přechod odměna: jméno zóny a kolik Poweru stála zeď,
	kterou k ní musel prorazit.

	Visí nad tratí u kraje, ne uprostřed — uprostřed by zakrývala zeď,
	na kterou hráč běží.
]]
--[[
	Žebra nad hlavou.

	Chodba měla dvě zdi a otevřené nebe, takže to nebyl tunel, ale příkop.
	Rozdíl je v tom, co dělá strop: dává rychlosti měřítko. Souvislá deska
	by ale sebrala světlo a hra by ztmavla, takže je to mříž — trámy přes
	chodbu a mezi nimi díra na oblohu.

	Spodek trámu nese barvu zóny, ve které leží. Hráč tak vidí přechod
	i nahoře, ne jen pod nohama, a když projde zdí, změní se mu celý
	prostor naráz.
]]
local function buildRibs(world, origin: Vector3, length: number, parent: Instance)
	local SPACING = 16
	local HEIGHT = 25.2

	local count = math.floor(length / SPACING)

	for index = 0, count do
		local z = index * SPACING - 40

		-- Nad startovní plošinou žádný strop: tam se hráč rozhlíží
		if z < 4 then
			continue
		end

		local zone = Zones.at(math.clamp(z // TRACK.SegmentLength + 1, 1, TRACK.BarrierCount))

		Build.part({
			Name = `Žebro {zone.Id}`,
			Size = Vector3.new(TRACK.Width + 6, 1.4, 2.2),
			Position = origin + Vector3.new(0, HEIGHT, z),
			-- Barva stropu patří levelu, ne celé trati: nad máslem má být
			-- máslo, ne beton. Odstín na ni ale sedne podle světa.
			Color = Zones.palette(zone, world).Ceiling,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			Parent = parent,
		})

		--[[
			Sloupky ke stropu.

			Dokud byla trať chodba, žebra ležela na jejích stěnách. Hala
			má u dráhy jen zábradlí do sedmi studů, takže žebra zůstala
			viset ve vzduchu — a plovoucí trám nad hlavou vypadá jako
			chyba, ne jako strop.

			Sloupek jde jen ke každému čtvrtému žebru. Pod každým by z
			toho byl plot, který zakryje halu, kvůli které se to celé
			stavělo.
		]]
		if index % 4 == 0 then
			local top = TRACK.WallHeight - 1
			for _, side in { -1, 1 } do
				Build.part({
					Name = "Sloupek stropu",
					Size = Vector3.new(1.8, HEIGHT - 0.7 - top, 1.8),
					Position = origin
						+ Vector3.new(
							side * (TRACK.Width / 2 + 1),
							(HEIGHT - 0.7 + top) / 2,
							z
						),
					Color = Config.Theme.Panel,
					Material = Enum.Material.Plastic,
					Surface = Enum.SurfaceType.Studs,
					CanCollide = false,
					Parent = parent,
				})
			end
		end

		--[[
			Svítí jen každé druhé žebro. Kdyby svítila všechna, splyne to
			v jeden pás a takt se ztratí — a přesně ten takt je to, kvůli
			čemu je strop cítit jako rychlost.
		]]
		if index % 2 == 0 then
			local glow = Build.part({
				Name = "Svit žebra",
				Size = Vector3.new(TRACK.Width - 2, 0.4, 0.8),
				Position = origin + Vector3.new(0, HEIGHT - 0.9, z),
				Color = zone.Edge,
				Material = Enum.Material.Neon,
				Transparency = 0.25,
				CanCollide = false,
				CastShadow = false,
				Parent = parent,
			})
			glow.Reflectance = 0.2
		end
	end
end

--[[
	Cedule levelu na stěně.

	Byl to malý sloupek u kraje s plovoucím nápisem. Ve velkých hrách
	žánru visí na stěně **velké cedule** — "x100 SPEED", "x25" — a jsou
	to ony, co dělají ze stěny kus světa místo barevné plochy.

	Cedule visí na obou stěnách, aby ji hráč viděl, ať kouká kam chce,
	a nese jméno levelu i pořadí. Text jde přes `SurfaceGui`, takže se
	nedeformuje s odstupem jako plovoucí popisek a čte se i z konce
	chodby.
]]
local function buildZoneSign(world, worldIndex: number, barrierIndex: number, parent: Instance)
	local zone = Zones.startsAt(barrierIndex)
	if not zone then
		return
	end

	local baseZ = Track.barrierPosition(worldIndex, barrierIndex).Z - TRACK.SegmentLength / 2

	for _, side in { -1, 1 } do
		local board = Build.part({
			Name = `Cedule {zone.Id}`,
			Size = Vector3.new(1, 22, 44),
			--[[
				Cedule visí na vzdálené stěně haly, ne u dráhy.

				Když byla trať uzavřená chodba, byla cedule na jejích
				stěnách jediné možné místo. Hala má stěny daleko a vysoko
				— přesně tam, kde ve velkých hrách žánru visí velké nápisy
				("x100 SPEED"). Musí být proto o dost větší: z devadesáti
				studů je malá cedule nečitelná skvrna.
			]]
			Position = Vector3.new(
				Track.origin(worldIndex).X + side * (TRACK.HallWidth / 2 - 3.4),
				20 - TRACK.DeckDrop,
				baseZ
			),
			Color = zone.Ceiling,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			CastShadow = false,
			Parent = parent,
		})

		-- Rám ve barvě levelu; bez něj cedule splyne se stěnou za sebou
		local frame = Build.part({
			Name = "Rám cedule",
			Size = Vector3.new(0.6, 24, 46),
			Position = Vector3.new(
				Track.origin(worldIndex).X + side * (TRACK.HallWidth / 2 - 2.6),
				20 - TRACK.DeckDrop,
				baseZ
			),
			Color = zone.Edge,
			Material = Enum.Material.Neon,
			Transparency = 0.2,
			CanCollide = false,
			CastShadow = false,
			Parent = parent,
		})
		Build.light(frame, zone.Edge, 1.6, 26)

		--[[
			Nápis kouká dovnitř chodby. Levá stěna má text na pravé
			straně dílu a naopak — kdyby obě měly stejnou, jedna by
			svítila ven do prázdna.
		]]
		local surface = Instance.new("SurfaceGui")
		surface.Name = "Nápis"
		surface.Face = if side < 0 then Enum.NormalId.Right else Enum.NormalId.Left
		surface.CanvasSize = Vector2.new(520, 240)
		surface.LightInfluence = 0
		surface.Adornee = board
		surface.Parent = board

		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(1, -20, 0.56, 0)
		name.Position = UDim2.fromOffset(10, 10)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.LuckiestGuy
		name.Text = string.upper(zone.Name)
		name.TextColor3 = zone.Edge
		name.TextScaled = true
		name.Parent = surface

		local stroke = Instance.new("UIStroke")
		stroke.Color = Config.Theme.Outline
		stroke.Thickness = 5
		stroke.Parent = name

		local rank = Instance.new("TextLabel")
		rank.Size = UDim2.new(1, -20, 0.32, 0)
		rank.Position = UDim2.new(0, 10, 0.62, 0)
		rank.BackgroundTransparency = 1
		rank.Font = Enum.Font.LuckiestGuy
		rank.Text = `LEVEL {barrierIndex} / {TRACK.BarrierCount}`
		rank.TextColor3 = Config.Theme.Text
		rank.TextScaled = true
		rank.Parent = surface

		local rankStroke = Instance.new("UIStroke")
		rankStroke.Color = Config.Theme.Outline
		rankStroke.Thickness = 4
		rankStroke.Parent = rank
	end
end

--[[
	Rekvizity světa.

	Popis je v `Shared.Props`, tady se z něj skládají díly. Barvy se
	v datech uvádějí jménem role, ne hexem — dosadí se až tady, takže
	jedna rekvizita může posloužit víc světům a nikde se neopisuje.
]]
--[[
	Povrchová výzdoba levelu.

	Tohle je ta vrstva, která z barevné chodby dělá kus hmoty: díry
	v sýru, posyp na koblize, papírový pás na másle, kůrka na chlebu.
	Bez ní by se levely lišily jen odstínem a hráč by po třetí zdi
	přestal rozdíl vnímat.

	Rozmístění se počítá z indexu, ne z náhody — svět tak vypadá na
	každém serveru stejně a dá se reprodukovat, když si někdo stěžuje,
	že mu díra trčí do cesty.

	Kusy nemají kolizi. Hráč běží po podlaze; kdyby o výzdobu zakopával,
	byla by z hezké vrstvy překážková dráha.
]]
local function decorSeed(barrierIndex: number, index: number): number
	local value = barrierIndex * 2654 + index * 4099
	value = (value * 1103) % 65536
	return value / 65536
end

local function buildDecor(zone, worldIndex: number, barrierIndex: number, parent: Instance)
	if not Zones.hasDecor(zone.Decor) then
		return
	end

	local origin = Track.origin(worldIndex)
	local baseZ = (barrierIndex - 1) * TRACK.SegmentLength
	local half = TRACK.Width / 2

	--[[
		Kolik kusů. Díry a posyp musí být hodně, aby vznikl dojem
		materiálu; papír je jeden pás a rýhy pár. Víc než dvacet na
		úsek už na telefonu stojí víc, než přidá.
	]]
	local counts = {
		holes = 16,
		bubbles = 14,
		sprinkles = 20,
		crust = 8,
		shards = 10,
		rivets = 12,
		dust = 12,
		wrapper = 2,
	}

	local count = counts[zone.Decor] or 10

	for index = 1, count do
		local roll = decorSeed(barrierIndex, index)
		local along = decorSeed(barrierIndex, index + 91)
		local z = baseZ + along * TRACK.SegmentLength

		if zone.Decor == "wrapper" then
			--[[
				Papírový pás přes obě stěny, přesně jako obal na hračce.
				Dva kusy, ne dvacet: obal je jeden a nemá být rozsypaný.
			]]
			local side = if index == 1 then -1 else 1
			local band = Build.part({
				Name = "Papír",
				Size = Vector3.new(0.4, 7, TRACK.SegmentLength * 0.5),
				Position = origin + Vector3.new(side * (half - 0.6), 9, baseZ + TRACK.SegmentLength / 2),
				Color = Color3.fromRGB(248, 244, 232),
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
				CastShadow = false,
				Parent = parent,
			})
			band.Reflectance = 0.08
			continue
		end

		if zone.Decor == "crust" then
			-- Kůrka: tmavší rýhy podél okrajů podlahy
			local side = if index % 2 == 0 then 1 else -1
			Build.part({
				Name = "Kůrka",
				Size = Vector3.new(2.6, 0.5, 5 + roll * 7),
				Position = origin + Vector3.new(side * (half - 3), 0.2, z),
				Color = zone.Ceiling,
				Material = Enum.Material.Sand,
				CanCollide = false,
				CastShadow = false,
				Parent = parent,
			})
			continue
		end

		if zone.Decor == "rivets" then
			-- Nýty na stěnách: jediná výzdoba, která patří kovu
			local side = if index % 2 == 0 then 1 else -1
			local rivet = Build.part({
				Name = "Nýt",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(0.9, 0.9, 0.9),
				Position = origin + Vector3.new(side * (half - 0.4), 3 + roll * 14, z),
				Color = zone.Edge,
				Material = Enum.Material.Metal,
				CanCollide = false,
				CastShadow = false,
				Parent = parent,
			})
			rivet.Reflectance = 0.9
			continue
		end

		--[[
			Zbytek se rozhazuje po podlaze i po stěnách. Střídání je
			podle indexu, ne podle losu: kdyby to bylo náhodné, občas
			by vyšel úsek, kde je všechno jen dole.
		]]
		local onWall = index % 3 == 0
		local size, color, material, shape

		--[[
			Drobnosti na povrchu se obarvují spolu s ním. Kdyby zůstaly
			v původní barvě levelu, vystoupily by v každém dalším světě
			z podlahy jako nálepky z jiné hry.

			Posyp je výjimka: nese barvu pickupu a ta musí zůstat, aby
			se posyp na podlaze nepletl se sbíratelnou drobností.
		]]
		local shade = Zones.palette(zone, Config.Worlds[worldIndex])

		if zone.Decor == "holes" then
			size = 1.6 + roll * 3.4
			color = shade.Ceiling
			material = Enum.Material.SmoothPlastic
			shape = Enum.PartType.Ball
		elseif zone.Decor == "bubbles" then
			size = 1 + roll * 2.6
			color = shade.Edge
			material = Enum.Material.SmoothPlastic
			shape = Enum.PartType.Ball
		elseif zone.Decor == "sprinkles" then
			size = 0.9 + roll * 0.6
			color = zone.Pickup.Color
			material = Enum.Material.SmoothPlastic
			shape = Enum.PartType.Block
		elseif zone.Decor == "shards" then
			size = 1.2 + roll * 2.2
			color = shade.Edge
			material = Enum.Material.Glass
			shape = Enum.PartType.Block
		else -- dust
			size = 0.7 + roll * 1.1
			color = shade.Edge
			material = Enum.Material.SmoothPlastic
			shape = Enum.PartType.Ball
		end

		local across = (roll * 2 - 1) * (half - 4)
		--[[
			Výzdoba na stěně patří na **stěnu haly**, ne k dráze.

			Původně visela na stěnách chodby. Ty jsou dneska zábradlí do
			sedmi studů, takže z výzdoby ve výšce dvaceti studů zbyly
			kusy plovoucí ve vzduchu — potřetí ta samá chyba: něco se
			posunulo a to, co na tom viselo, ne.

			Stěna haly je zároveň jediná velká plocha, kterou hráč z
			dráhy vidí celou. Ve velkých hrách žánru je právě na ní
			všechno to, co dělá pozadí.
		]]
		local wallSide = if across < 0 then -1 else 1
		local position = if onWall
			then origin + Vector3.new(
				wallSide * (TRACK.HallWidth / 2 - 0.5),
				4 + along * 34 - TRACK.DeckDrop,
				z
			)
			else origin + Vector3.new(across, 0.1, z)

		local piece = Build.part({
			Name = `Výzdoba {zone.Id}`,
			Shape = shape,
			--[[
				Ploché, ne kulaté: kus zapuštěný do povrchu vypadá jako
				díra nebo skvrna. Koule postavená na podlaze vypadá jako
				zapomenutý míč.
			]]
			Size = Vector3.new(size, size * 0.45, size),
			Position = position,
			Color = color,
			Material = material,
			CanCollide = false,
			CastShadow = false,
			Parent = parent,
		})

		if zone.Decor == "sprinkles" then
			-- Posyp leží nakřivo; srovnaný by vypadal jako mozaika
			piece.CFrame = CFrame.new(position) * CFrame.Angles(0, roll * math.pi * 2, math.rad(12))
		end

		piece.Reflectance = zone.Reflectance * 0.6
		piece.Transparency = zone.Transparency
	end
end

--[[
	Obří hračka u trati.

	Ve velkých hrách žánru stojí kolem trati velké, poznatelné věci —
	metrová lízátka, sušenky, cukrové hole. Chodba s abstraktními
	sloupy vedle toho vypadá levně, i když je barevná.

	Nemusí se kvůli tomu nic modelovat: postaví se ta samá hračka
	z `Shared.Toy`, jen šestnáctkrát větší. Hráč tedy vidí u trati
	přesně to, co drží v ruce a co má na sobě celý level — a když se
	recept změní, změní se obojí naráz.
]]
--[[
	Velikost a místo.

	První verze je stavěla ZA postranní stěny — a ty jsou neprůhledné,
	takže je ve hře nikdo nikdy neviděl. Sto padesát dílů výzdoby, která
	fyzicky existovala a nešla spatřit.

	Chvíli visely uvnitř dráhy nad hlavou — jediné místo, kde byly
	v uzavřené chodbě vidět. Jakmile z chodby vznikla hala, mají kam:
	stojí na terase vedle dráhy, kde je nic neomezuje, a přes nízké
	zábradlí je vidět celé. Můžou tím pádem být dvakrát tak velké.

	Přesně jako ty velké cukrovinky, které v referenčních hrách stojí
	kolem trati.
]]
local GIANT_SCALE = 24
local GIANT_HEIGHT = 6

--[[
	Spodní řádek cenovky.

	"REWARD ONLY" u všeho, co nemá cenu, je horší než nic: hráč z toho
	nezjistí, jestli si tu hračku má vydřít, počkat na ni, nebo ji
	dávno má. Startovní hračka je přesně ten případ — visela nad ní
	cedule slibující odměnu za něco, co hráč dostal na startu zdarma.
]]
local function priceLine(squishy): string
	if squishy.Id == Live.Starter then
		return "YOURS FROM THE START"
	elseif squishy.Id == Live.FinalReward then
		return "BEAT THE LAST WORLD"
	elseif squishy.Price > 0 then
		return `💰 {Format.short(squishy.Price)}`
	end

	return "REWARD ONLY"
end

local function buildGiant(zone, worldIndex: number, barrierIndex: number, parent: Instance)
	local squishy = Live.squishy(zone.Toy)
	if not squishy then
		return
	end

	local origin = Track.origin(worldIndex)
	local baseZ = (barrierIndex - 1) * TRACK.SegmentLength + TRACK.SegmentLength * 0.35

	--[[
		Střídají se strany, aby trať nebyla těžká na jednu stranu.
		Sudý level vpravo, lichý vlevo — a protože je level na každou
		zeď, znamená to jednu rekvizitu na každou stranu každou zeď.
	]]
	local side = if barrierIndex % 2 == 0 then 1 else -1
	local center = origin
		+ Vector3.new(side * (TRACK.Width / 2 + 30), GIANT_HEIGHT, baseZ)

	for index, piece in Toy.pieces(squishy) do
		local rotation = piece.Rotation or Vector3.zero

		local part = Build.part({
			Name = `Obří {squishy.Id} {index}`,
			Shape = (Enum.PartType :: any)[piece.Kind] or Enum.PartType.Block,
			Size = piece.Size * GIANT_SCALE,
			CFrame = CFrame.new(center + piece.Offset * GIANT_SCALE)
				* CFrame.Angles(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z)),
			Color = Toy.colorFor(piece.Role, squishy.Color, piece.Color),
			Material = Enum.Material.SmoothPlastic,
			Reflectance = piece.Reflectance or 0.1,
			Transparency = piece.Transparency or 0,
			CanCollide = false,
			Parent = parent,
		})

		--[[
			Ke které zdi rekvizita patří. Klient podle toho pozná, kterou
			hračku má při průrazu zmáčknout — obří máslo se při proražení
			máslové zdi promáčkne stejně jako to v ruce.

			Atribut, ne jméno: jméno nese id hračky a to se ve světě
			opakuje, kdežto zeď je jedna.
		]]
		part:SetAttribute("Giant", barrierIndex)
		part:SetAttribute("Squish", zone.Squish)
		part:SetAttribute("WorldId", Config.Worlds[worldIndex].Id)
		--[[
			Značka ze stejného důvodu jako u vznášejících se rekvizit:
			jednorázový průchod stromem najde jen to, co je v okamžiku
			stavby světa u hráče načtené, a to je se streamingem sotva
			polovina trati.
		]]
		CollectionService:AddTag(part, "GiantToy")
	end

	--[[
		Cenovka pod rekvizitou. Obří sýr u trati sám o sobě neřekne, že
		je to zboží — hráč kolem něj proběhne dvanáctkrát a nikdy ho
		nenapadne otevřít obchod.

		Cena se bere z katalogu, ne opisuje: kdyby se čísla rozešla,
		poznal by to hráč až tím, že mu obchod řekne jinou částku, než
		na kterou si šetřil.
	]]
	--[[
		Barvu cedule řídí vzácnost, ne třída hračky.

		Třída (Soft/Chewy/Dense) říká, jak se hračka mačká — to je
		vlastnost hraní. Cenovka u trati odpovídá na jinou otázku:
		"jsem na tohle už dost daleko?" A na tu odpovídá vzácnost.
	]]
	local tier = Live.squishyRarity(squishy.Id)
	local plaque = Build.part({
		--[[
			Ne "Cedule": tak se jmenují nápisy levelů na stěnách haly
			a test, který je počítá, by tyhle připočetl k nim.
		]]
		Name = `Cenovka {squishy.Id}`,
		Size = Vector3.new(18, 1, 1),
		Position = center - Vector3.new(0, GIANT_HEIGHT - 1, 0)
			+ Vector3.new(0, 0, -side * 2),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
		Parent = parent,
	})

	Build.billboard({
		Adornee = plaque,
		Text = `<b>{string.upper(squishy.Name)}</b>\n{tier.Name}  ·  {priceLine(squishy)}`,
		Size = UDim2.fromScale(20, 7),
		Offset = Vector3.new(0, 3, 0),
		Color = tier.Color,
		MaxDistance = 420,
	})
end

local function resolveColor(role: string, world): Color3
	if role == "Accent" then
		return world.Accent
	elseif role == "Dark" then
		return world.Fog:Lerp(Color3.new(0, 0, 0), 0.25)
	elseif role == "Light" then
		return world.Color:Lerp(Color3.new(1, 1, 1), 0.45)
	end
	return world.Color
end

local SHAPES = {
	Block = Enum.PartType.Block,
	Ball = Enum.PartType.Ball,
	Cylinder = Enum.PartType.Cylinder,
	Wedge = Enum.PartType.Wedge,
}

local function buildProp(prop, world, base: CFrame, parent: Instance)
	local model = Instance.new("Model")
	model.Name = prop.Id
	model.Parent = parent

	for _, item in prop.Pieces do
		local rotation = item.Rotation or Vector3.zero
		local part = Build.part({
			Name = prop.Id,
			Size = item.Size,
			CFrame = base
				* CFrame.new(item.Offset)
				* CFrame.Angles(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z)),
			Color = resolveColor(item.Color, world),
			Material = (Enum.Material :: any)[item.Material] or Enum.Material.SmoothPlastic,
			Transparency = item.Transparency or 0,
			Shape = SHAPES[item.Shape],
			-- Rekvizity stojí mimo trať, takže do nich hráč nemůže vrazit.
			-- Bez kolize navíc nestojí nic na fyzice.
			CanCollide = false,
			Parent = model,
		})

		if item.Glow then
			Build.light(part, resolveColor(item.Color, world), item.Glow, 16)
		end

		--[[
			Vznášející se rekvizita se označí atributem. Klient si takové
			díly posbírá a animuje je v jedné smyčce — server na to nesahá,
			protože pohyb, který nikoho neovlivňuje, nepatří na server.
		]]
		if prop.Float then
			markFloater(part, prop.Float, world.Id)
		end
	end
end

--[[
	Rozestavění rekvizit podél trati.

	Jde se po úsecích mezi zdmi a u každého se zkusí každá rekvizita.
	`Every` říká, po kolika úsecích se opakuje — tím vzniká rytmus
	a ne les.
]]
local function buildProps(world, worldIndex: number, parent: Instance)
	local props = Props.forWorld(world.Id)
	if #props == 0 then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "Rekvizity"
	folder.Parent = parent

	local origin = Track.origin(worldIndex)

	for segment = 0, TRACK.BarrierCount do
		local z = segment * TRACK.SegmentLength - TRACK.SegmentLength / 2

		for _, prop in props do
			if segment % prop.Every ~= 0 then
				continue
			end

			for _, side in Props.sides(prop) do
				--[[
					Natočení dovnitř: rekvizita vlevo se otočí doprava
					a naopak. Bez toho by všechny koukaly stejným směrem
					a jedna strana trati by vypadala odvráceně.
				]]
				local yaw = if side == 0 then 0 else -side * math.rad(14)

				--[[
					Rekvizita za zábradlím stojí na terase, a ta je o šest
					studů níž než dráha. Bez toho posunu se všechny
					rekvizity vznášely přesně o výšku terasy nad zemí —
					což je typ chyby, který ve Studiu vypadá jako záměr,
					dokud si člověk nestoupne vedle.
				]]
				local onDeck = side ~= 0 and prop.Distance > TRACK.Width / 2
				local drop = if onDeck then TRACK.DeckDrop else 0

				local base = CFrame.new(
					origin + Vector3.new(side * prop.Distance, prop.Height - drop, z)
				) * CFrame.Angles(0, yaw, 0)

				buildProp(prop, world, base, folder)
			end
		end
	end
end

--[[
	Nákupní pady na trati.

	Ve velkých hrách žánru se vylepšení nekupují jen v menu — stojí na
	nich přímo na trati a hráč si na ně stoupne. Rozdíl není v pohodlí,
	ale v tom, že je svět **něčím obsazený**: chodba s pár deskami
	a cedulemi vypadá jako hřiště, prázdná chodba jako tunel.

	Pady se opakují po celé délce, ne jen u startu. Hráč se k prvnímu
	dostane hned, ale v desátém levelu by mu byl k ničemu, kdyby se
	musel vracet.
]]
local PAD_EVERY = 3

--[[
	Odrazové můstky.

	Jedna řada pickupů v každém segmentu visí osm studů nad zemí (viz
	`Config.Track.RaisedRow`) a základní dosah sbírání je sedm — ze země
	se na ni tedy nedosáhne. Můstek je odpověď: stoupneš na něj a letíš
	přesně skrz ni.

	Stojí kousek PŘED tou řadou, ne pod ní. Odraz má vrchol až po chvíli
	letu, takže můstek přímo pod pickupy by hráče vystřelil až za ně.

	Přeskočit se to dá: kdo si vylepší Magnet, dosáhne na vyvýšenou řadu
	i ze země. Můstek je zkratka pro toho, kdo Magnet ještě nemá, ne
	povinná překážka — povinný skok uprostřed běhu by na telefonu
	rozbíjel combo víc, než by přidával.
]]
local function buildBouncers(world, worldIndex: number, parent: Instance)
	local origin = Track.origin(worldIndex)
	local rowZ = TRACK.RowOffsets[TRACK.RaisedRow]

	for step = 0, TRACK.BarrierCount - 1 do
		local z = step * TRACK.SegmentLength + rowZ - 14

		local pad = Build.part({
			Name = "Odrazový můstek",
			-- Přes celou šířku dráhy: hráč nemá uhýbat do pruhu, má běžet
			Size = Vector3.new(TRACK.Width - 10, 1, 8),
			Position = origin + Vector3.new(0, Config.floorTop() + 0.6, z),
			Color = world.Accent,
			Material = Enum.Material.Neon,
			Transparency = 0.15,
			TopSurface = Enum.SurfaceType.Studs,
			CanCollide = false,
			CastShadow = false,
			Parent = parent,
		})
		pad:SetAttribute("WorldId", world.Id)
		CollectionService:AddTag(pad, "BouncePad")
		Build.light(pad, world.Accent, 2, 22)

		-- Rám kolem: bez něj se neonový obdélník ztratí v podlaze levelu
		Build.part({
			Name = "Rám můstku",
			Size = Vector3.new(TRACK.Width - 8, 0.4, 9.4),
			Position = origin + Vector3.new(0, Config.floorTop() - 0.1, z),
			Color = Config.Theme.Gold,
			Material = Enum.Material.Neon,
			Transparency = 0.3,
			CanCollide = false,
			CastShadow = false,
			Parent = parent,
		})
	end
end

local function buildPads(world, worldIndex: number, parent: Instance)
	local origin = Track.origin(worldIndex)
	local upgrades = Config.Upgrades
	local count = #upgrades

	--[[
		Desky leží v jedné řadě napříč tratí, hráči přímo v cestě.

		Původně stály u krajů, aby si hráč nekupoval omylem — jenže tam
		nikdo nechodí, takže je nikdy neuviděl a nekupoval vůbec. Ve
		velkých hrách žánru je to naopak: řada zelených desek přes celou
		šířku, proběhneš jimi a nakoupíš. Není to nepozornost, je to
		celý způsob, jak se v téhle hře utrácí.

		Šířka se dělí mezi ně rovnoměrně, takže přidání šestého
		vylepšení do configu nic nerozhodí.
	]]
	local slot = TRACK.Width / count
	local width = slot - 1.6

	for step = 0, TRACK.BarrierCount, PAD_EVERY do
		local zone = Zones.at(math.clamp(step + 1, 1, TRACK.BarrierCount))
		local z = step * TRACK.SegmentLength + 14

		for index, upgrade in upgrades do
			local across = (index - (count + 1) / 2) * slot

			local pad = Build.part({
				Name = `Pad {upgrade.Id}`,
				Size = Vector3.new(width, 1.2, 11),
				--[[
					Deska leží NAD dlaždicemi, ne v nich.

					Dlaždice podlahy jsou dva a půl studu vysoké kostky,
					které staví klient. Deska ve výšce jednoho studu by
					v nich byla pohřbená a hráč by ji nikdy neuviděl —
					další kus výzdoby, který existuje a není odkud
					spatřit.
				]]
				Position = origin + Vector3.new(across, Config.floorTop() + 0.7, z),
				Color = Config.Theme.Acid,
				Material = Enum.Material.SmoothPlastic,
				TopSurface = Enum.SurfaceType.Studs,
				CanCollide = false,
				CastShadow = false,
				Parent = parent,
			})
			pad:SetAttribute("Upgrade", upgrade.Id)
			CollectionService:AddTag(pad, "BuyPad")

			-- Rám kolem desky: bez něj pad splyne s podlahou levelu
			Build.part({
				Name = "Rám padu",
				Size = Vector3.new(width + 1.2, 0.5, 12.2),
				Position = origin + Vector3.new(across, Config.floorTop() - 0.15, z),
				Color = zone.Edge,
				Material = Enum.Material.Neon,
				Transparency = 0.25,
				CanCollide = false,
				CastShadow = false,
				Parent = parent,
			})

			--[[
				Cedule nad deskou. Visí nízko, aby se řada cedulí
				nepřekrývala s obřími hračkami nad hlavou, a text
				doplňuje klient podle profilu — cena roste s úrovní
				a server ji stejně přepočítá, takže by pevný nápis lhal.
			]]
			local _, label = Build.billboard({
				Adornee = pad,
				Text = `<b>{upgrade.Icon} {string.upper(upgrade.Name)}</b>`,
				Size = UDim2.fromScale(9, 3.4),
				Offset = Vector3.new(0, 5, 0),
				Color = Config.Theme.Text,
				MaxDistance = 220,
			})
			label.Name = "PadText"
		end
	end
end

--[[
	Hala kolem dráhy.

	Tohle je ta věc, kterou barvy ani textury nenahradí. Dráha vedla
	uzavřenou rourou; ve velkých hrách žánru běží uprostřed velké
	místnosti, kde je po stranách vidět daleko, u vzdálených stěn stojí
	rekvizity a nad tím vším je vysoký strop.

	Mělo to i praktický následek: cokoliv postaveného vedle dráhy bylo
	za neprůhlednou stěnou a nešlo to spatřit. Stalo se to třikrát po
	sobě — obřím rekvizitám, plovoucím krám i nákupním deskám.

	Hala je schválně z mála velkých dílů: dvě podlahy, dvě stěny, jeden
	strop na svět. Velký díl s nopy vypadá stejně dobře jako sto malých
	a stojí zlomek.
]]
--[[
	Označí díl, který má svítit s combem.

	Zářivky v hale nejsou ozdoba: jsou to jediné velké plochy, které
	můžou na hraní reagovat. Když se hráči rozjede řetěz, rozsvítí se
	s ním celá místnost — a to je zpětná vazba, kterou vidí i ten, kdo
	se zrovna nedívá na kartu v rohu.

	Značka, ne jednorázový průchod stromem: se streamingem dorazí
	vzdálená polovina haly k hráči až cestou.
]]
local function markGlow(part: BasePart, base: Color3, peak: Color3, worldId: string)
	part:SetAttribute("GlowBase", base)
	part:SetAttribute("GlowPeak", peak)
	part:SetAttribute("WorldId", worldId)
	CollectionService:AddTag(part, "WallGlow")
end

--[[
	Hala kolem dráhy.

	Tohle je ta věc, kterou barvy ani textury nenahradí. Dráha vedla
	uzavřenou rourou; ve velkých hrách žánru běží uprostřed velké
	místnosti, kde je po stranách vidět daleko, u vzdálených stěn stojí
	rekvizity a nad tím vším je vysoký strop.

	Mělo to i praktický následek: cokoliv postaveného vedle dráhy bylo
	za neprůhlednou stěnou a nešlo to spatřit. Stalo se to třikrát po
	sobě — obřím rekvizitám, plovoucím krám i nákupním deskám.

	══ Proč to není jen šest desek ══

	Byla to jedna plochá stěna na stranu, jeden plochý strop a jedna
	plochá terasa, každá v jednom odstínu. Z pohledu hráče to znamenalo
	tři obrovské jednobarevné plochy, na kterých se oko nemá čeho
	chytit — a i když je barva světa jiná, dojem je v každém světě
	stejný: prázdno.

	Stěna má proto teď to, co má každá skutečná stěna: **sokl** dole,
	**pilastry** ve svislém rytmu, dva pásy **zářivek** a **římsu**
	nahoře. Není to detail kvůli detailu: svislé členění dává chodbě
	měřítko (hráč vidí, jak rychle běží, protože kolem něj něco ubíhá)
	a vodorovné pásy dávají výšku (hala působí vysoko, protože je čím
	měřit).

	Rytmus je schválně řídký — pilastr po čtyřiceti studech, zářivka
	přes celou délku jedním dílem. Hustší členění by vypadalo stejně
	dobře a stálo desetkrát víc dílů.
]]
local function buildHall(world, origin: Vector3, length: number, centerZ: number, parent: Instance)
	local half = TRACK.HallWidth / 2
	local deckWidth = half - TRACK.Width / 2
	local floorY = -2 - TRACK.DeckDrop

	--[[
		Barvy haly. Odvozují se z barvy světa, ale každá plocha jinak —
		kdyby všechny vyšly ze stejného lerpu, splynou v jednu.
	]]
	local deckColor = world.Color:Lerp(Config.Theme.Ink, 0.45)
	local wallColor = world.Color:Lerp(Config.Theme.Ink, 0.25)
	local trimColor = world.Accent:Lerp(Config.Theme.Ink, 0.15)
	local glowColor = world.Color:Lerp(Color3.new(1, 1, 1), 0.25)

	for _, side in { -1, 1 } do
		--[[
			Podlaha haly je níž než dráha, takže z dráhy zůstane vyvýšená
			cesta. Bez toho výškového rozdílu splyne dráha s halou
			a přestane být poznat, kudy se běží.
		]]
		Build.part({
			-- Ne "Podlaha …": tak se jmenují úseky dráhy a test podle
			-- toho počítá levely, takže by se mu do nich hala připletla
			Name = "Terasa",
			Size = Vector3.new(deckWidth, 4, length),
			Position = origin
				+ Vector3.new(side * (TRACK.Width / 2 + deckWidth / 2), floorY, centerZ),
			Color = deckColor,
			Material = Enum.Material.Plastic,
			TopSurface = Enum.SurfaceType.Studs,
			Parent = parent,
		})

		-- Vzdálená stěna: to, co dělá halu halou a co hráč vidí přes zábradlí
		Build.part({
			Name = "Stěna haly",
			Size = Vector3.new(6, TRACK.HallHeight, length),
			Position = origin
				+ Vector3.new(side * (half + 3), TRACK.HallHeight / 2 - TRACK.DeckDrop, centerZ),
			Color = wallColor,
			Material = Enum.Material.Plastic,
			Surface = Enum.SurfaceType.Studs,
			Parent = parent,
		})

		--[[
			Sokl. Spodní metr každé stěny je ve skutečnosti vždycky jiný
			než zbytek — a je to ten kus, který má hráč nejblíž u oka,
			protože běží po zemi.
		]]
		Build.part({
			Name = "Sokl haly",
			Size = Vector3.new(3, 5, length),
			Position = origin + Vector3.new(side * (half - 1.5), floorY + 4.5, centerZ),
			Color = trimColor,
			Material = Enum.Material.SmoothPlastic,
			Surface = Enum.SurfaceType.Studs,
			CanCollide = false,
			Parent = parent,
		})

		--[[
			Římsa nahoře. Uzavírá stěnu, aby nekončila do prázdna, a
			zároveň zakrývá šev mezi stěnou a stropem.
		]]
		Build.part({
			Name = "Římsa haly",
			Size = Vector3.new(8, 4, length),
			Position = origin
				+ Vector3.new(side * (half - 1), TRACK.HallHeight - TRACK.DeckDrop - 4, centerZ),
			Color = trimColor,
			Material = Enum.Material.SmoothPlastic,
			Surface = Enum.SurfaceType.Studs,
			CanCollide = false,
			Parent = parent,
		})

		--[[
			Dva pásy zářivek přes celou délku. Nízký svítí hráči pod nohy,
			vysoký kreslí perspektivu — dvě rovnoběžky mizící v dálce jsou
			nejlevnější způsob, jak z chodby udělat prostor.
		]]
		for _, strip in { { Height = 14, Thick = 1.6 }, { Height = 40, Thick = 2.4 } } do
			local bar = Build.part({
				Name = "Zářivka haly",
				Size = Vector3.new(1.2, strip.Thick, length - 8),
				Position = origin
					+ Vector3.new(side * (half - 3.4), floorY + strip.Height, centerZ),
				Color = glowColor,
				Material = Enum.Material.Neon,
				Transparency = 0.1,
				CanCollide = false,
				CastShadow = false,
				Parent = parent,
			})
			markGlow(bar, glowColor, Config.Theme.Text, world.Id)
		end

		--[[
			Pilastry. Svislé sloupky ve stěně po čtyřiceti studech: bez
			nich je stěna jedna plocha dlouhá tisíc studů a hráč z ní
			nepozná, jestli běží, nebo stojí.
		]]
		local pilasterStep = 48
		local count = math.floor(length / pilasterStep)
		for index = 0, count do
			local z = centerZ - length / 2 + 20 + index * pilasterStep
			if z > centerZ + length / 2 - 10 then
				break
			end

			Build.part({
				Name = "Pilastr haly",
				Size = Vector3.new(5, TRACK.HallHeight - 12, 7),
				Position = origin + Vector3.new(
					side * (half - 2.5),
					floorY + (TRACK.HallHeight - 12) / 2 + 4,
					z
				),
				Color = world.Accent:Lerp(Config.Theme.Ink, 0.35),
				--[[
					Materiál světa, ne jednotný plast. Je to jediné místo
					v hale, kde je povrch vidět zblízka — sklo v Glass
					Hall a čokoláda v Chocolate Factory tam mají vypadat
					jinak, ne jen mít jinou barvu.
				]]
				Material = world.Material,
				Surface = Enum.SurfaceType.Studs,
				Reflectance = 0.12,
				CanCollide = false,
				Parent = parent,
			})

			--[[
				Světelná hlavice pilastru. Rozsvítí prostor mezi sloupky,
				takže stěna není rovnoměrně nasvícená plocha, ale střídá
				světlo a stín — a právě to je na ní vidět.
			]]
			local cap = Build.part({
				Name = "Hlavice pilastru",
				Size = Vector3.new(4, 3, 8),
				Position = origin + Vector3.new(
					side * (half - 2.5),
					floorY + TRACK.HallHeight - 12,
					z
				),
				Color = world.Accent,
				Material = Enum.Material.Neon,
				Transparency = 0.15,
				CanCollide = false,
				CastShadow = false,
				Parent = parent,
			})
			Build.light(cap, world.Accent, 2.2, 46)
			markGlow(cap, world.Accent, Config.Theme.Text, world.Id)

			--[[
				Pás v podlaze terasy naproti pilastru. Podlaha byla jedna
				barva na tisíc studů; příčné pásy z ní udělají dlažbu
				a hráči pod nohama ubíhají, což je ten samý trik jako
				u pilastrů, jen naležato.
			]]
			Build.part({
				Name = "Pás terasy",
				Size = Vector3.new(deckWidth - 6, 0.4, 5),
				Position = origin + Vector3.new(
					side * (TRACK.Width / 2 + deckWidth / 2),
					floorY + 2.1,
					z
				),
				Color = world.Accent:Lerp(Config.Theme.Ink, 0.2),
				Material = Enum.Material.SmoothPlastic,
				Transparency = 0.25,
				CanCollide = false,
				CastShadow = false,
				Parent = parent,
			})
		end
	end

	--[[
		Strop haly s otevřeným pruhem uprostřed.

		Byla to jedna plná deska přes celou šířku. Hala tím byla
		zavřená krabice: obloha, mlha ani barva světa se do ní nedostaly
		a hráč běžel v místnosti bez venku.

		Uprostřed proto zůstává **štěrbina**, kterou je vidět nebe.
		Nestojí to nic — obloha už se podle světa přebarvuje — a přitom
		to dělá víc než jakákoliv textura: strop najednou něco nese,
		místnost má nad sebou prostor a světlo do ní padá shora.

		Trámy přes štěrbinu jsou tam ze stejného důvodu jako pilastry na
		stěně: bez nich by to nebyl otvor ve stropě, ale chybějící kus.
	]]
	local slot = 54
	local sideWidth = (TRACK.HallWidth + 12 - slot) / 2

	for _, side in { -1, 1 } do
		Build.part({
			Name = "Strop haly",
			Size = Vector3.new(sideWidth, 6, length),
			Position = origin + Vector3.new(
				side * (slot / 2 + sideWidth / 2),
				TRACK.HallHeight + 3 - TRACK.DeckDrop,
				centerZ
			),
			Color = world.Color:Lerp(Config.Theme.Ink, 0.6),
			Material = Enum.Material.Plastic,
			Surface = Enum.SurfaceType.Studs,
			Parent = parent,
		})
	end

	local beamStep = 48
	local beams = math.floor(length / beamStep)
	for index = 0, beams do
		local z = centerZ - length / 2 + 16 + index * beamStep
		if z > centerZ + length / 2 - 8 then
			break
		end

		Build.part({
			Name = "Trám stropu",
			Size = Vector3.new(slot + 4, 5, 4),
			Position = origin + Vector3.new(0, TRACK.HallHeight + 2 - TRACK.DeckDrop, z),
			Color = world.Accent:Lerp(Config.Theme.Ink, 0.4),
			Material = Enum.Material.Plastic,
			Surface = Enum.SurfaceType.Studs,
			CanCollide = false,
			Parent = parent,
		})
	end

	--[[
		Světelné panely ve stropě.

		Strop byl jedna tmavá deska nad hlavou a veškeré světlo přicházelo
		odjinud. Řada panelů dává hale strop, na který se dá koukat, a
		hlavně **shora dolů svítící světlo** — díky němu mají všechny
		rekvizity v hale stín a přestanou vypadat jako nálepky.
	]]
	local panelStep = 64
	local panels = math.floor(length / panelStep)
	for index = 0, panels do
		local z = centerZ - length / 2 + 32 + index * panelStep
		if z > centerZ + length / 2 - 20 then
			break
		end

		local panel = Build.part({
			Name = "Stropní panel",
			Size = Vector3.new(TRACK.HallWidth * 0.42, 1.4, 22),
			Position = origin + Vector3.new(0, TRACK.HallHeight - TRACK.DeckDrop - 0.5, z),
			Color = glowColor,
			Material = Enum.Material.Neon,
			Transparency = 0.12,
			CanCollide = false,
			CastShadow = false,
			Parent = parent,
		})
		Build.light(panel, glowColor, 2.6, 90)
		markGlow(panel, glowColor, Config.Theme.Text, world.Id)
	end
end

--[[
	Fyzikální rekvizity v hale.

	Celý svět byl do teď přikotvený: nic se nedalo strčit, nic
	nereagovalo na to, že tudy někdo běží. Hráč tak běžel kulisou, ne
	místem.

	Jsou tu dva druhy a každý dělá něco jiného:

	  * **lampiony na lanech** visí od stropu a rozhoupou se, když do
	    nich hráč narazí. Dávají hale pohyb i ve chvíli, kdy se nic
	    neděje — kývající se věc v periferním vidění je to, co odliší
	    živou scénu od obrázku.
	  * **kostky na terase** se dají odkopnout. Je to ta nejlevnější
	    hračka na světě a hráči s ní stráví víc času, než by kdo čekal.

	Je jich schválně málo. Fyzika se počítá na serveru a padesát
	kutálejících se kostek na svět by ho stálo víc než celý zbytek hry;
	deset kusů se navíc uspí, jakmile se přestanou hýbat.
]]
local function buildPhysics(world, worldIndex: number, parent: Instance)
	local origin = Track.origin(worldIndex)
	local half = TRACK.HallWidth / 2
	local deckWidth = half - TRACK.Width / 2
	local floorY = -2 - TRACK.DeckDrop

	for _, side in { -1, 1 } do
		local across = side * (TRACK.Width / 2 + deckWidth * 0.55)

		--[[
			Tři lampiony na stranu, rozeseté po délce trati. Víc by
			se v perspektivě slilo do jedné řady a přestaly by být
			jednotlivé.
		]]
		for index = 1, 3 do
			local z = TRACK.SegmentLength * (index * 3.5)

			--[[
				Kotva je přikotvená a bez kolize. Kdyby byla hmotná,
				visel by na ní lampion i s vlastní vahou a lano by se
				natáhlo přes půl haly.
			]]
			local hook = Build.part({
				Name = "Hák lampionu",
				Size = Vector3.new(1.2, 1.2, 1.2),
				Position = origin + Vector3.new(across, TRACK.HallHeight - TRACK.DeckDrop - 2, z),
				Color = Config.Theme.Ink,
				Material = Enum.Material.Metal,
				CanCollide = false,
				CastShadow = false,
				Parent = parent,
			})

			local bob = Build.part({
				Name = "Lampion",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(7, 7, 7),
				Position = origin + Vector3.new(across, TRACK.HallHeight - TRACK.DeckDrop - 26, z),
				Color = world.Accent,
				Material = Enum.Material.Neon,
				Transparency = 0.25,
				Anchored = false,
				--[[
					Kolize zapnutá: bez ní by hráč lampionem prošel
					a nikdy by ho nerozhoupal. To je celá pointa.
				]]
				CanCollide = true,
				CanTouch = true,
				CastShadow = false,
				Parent = parent,
			})
			Build.light(bob, world.Accent, 2, 34)

			local top = Instance.new("Attachment")
			top.Parent = hook

			local bottom = Instance.new("Attachment")
			bottom.Position = Vector3.new(0, 3.5, 0)
			bottom.Parent = bob

			local rope = Instance.new("RopeConstraint")
			rope.Attachment0 = top
			rope.Attachment1 = bottom
			rope.Length = 22
			rope.Visible = true
			rope.Color = BrickColor.new(Config.Theme.Ink)
			rope.Thickness = 0.2
			rope.Parent = hook
		end

		--[[
			Kostky u startu. Blízko placu schválně: hráč na ně narazí
			v první minutě, tedy přesně tehdy, kdy zjišťuje, co všechno
			ta hra dělá.
		]]
		for index = 1, 3 do
			Build.part({
				Name = "Kostka",
				Size = Vector3.new(4, 4, 4),
				Position = origin + Vector3.new(
					across + index * 5,
					floorY + 4,
					-14 + index * 9
				),
				Color = world.Color:Lerp(Color3.new(1, 1, 1), 0.2),
				Material = world.Material,
				Surface = Enum.SurfaceType.Studs,
				Anchored = false,
				CanCollide = true,
				CanTouch = true,
				Parent = parent,
			})
		end
	end
end

--[[
	Portál do dalšího světa.

	Světy se do teď kupovaly jen z menu, takže postup mezi nimi nebyl
	nikde vidět — hráč doběhl na konec trati a tam nebylo nic než
	nápis. Ve velkých hrách žánru stojí na konci **brána s cenou**:
	dojdeš k ní, vidíš, kolik stojí další svět, a vejdeš do ní.

	Za posledním světem se nestaví: není kam.
]]
local function buildPortal(worldIndex: number, parent: Instance)
	local nextWorld = Config.Worlds[worldIndex + 1]
	if not nextWorld then
		return
	end

	local position = Track.finishPosition(worldIndex) + Vector3.new(0, 0, 26)

	local pad = Build.part({
		-- Ne "Portál": tak se jmenují sloupy startovní brány a hledání
		-- podle jména by našlo je
		Name = "Brána světa",
		Size = Vector3.new(TRACK.Width - 8, 1.2, 14),
		Position = position + Vector3.new(0, Config.floorTop() - 3.3, 0),
		Color = nextWorld.Color,
		Material = Enum.Material.Neon,
		Transparency = 0.25,
		CanCollide = false,
		CastShadow = false,
		Parent = parent,
	})
	pad:SetAttribute("World", nextWorld.Id)
	CollectionService:AddTag(pad, "WorldPortal")
	Build.light(pad, nextWorld.Color, 3, 40)

	--[[
		Blána mezi sloupy. Průhledná a bez kolize: brána musí vypadat
		jako průchod, ne jako další zeď — těch má hráč za sebou dvanáct.
	]]
	local veil = Build.part({
		Name = "Blána brány",
		Size = Vector3.new(TRACK.Width - 6, 26, 0.6),
		Position = position + Vector3.new(0, 13, 0),
		Color = nextWorld.Accent,
		Material = Enum.Material.Neon,
		Transparency = 0.7,
		CanCollide = false,
		CastShadow = false,
		Parent = parent,
	})
	markFloater(veil, 0.15, Config.Worlds[worldIndex].Id)

	for _, side in { -1, 1 } do
		Build.part({
			Name = "Sloup brány",
			Size = Vector3.new(4, 30, 4),
			Position = position + Vector3.new(side * (TRACK.Width / 2 - 2), 15, 0),
			Color = nextWorld.Accent,
			Material = Enum.Material.Plastic,
			Surface = Enum.SurfaceType.Studs,
			CanCollide = false,
			Parent = parent,
		})
	end

	--[[
		Text doplňuje klient: cena je stejná pro všechny, ale to, jestli
		si ji hráč může dovolit a jestli svět už vlastní, se liší člověk
		od člověka.
	]]
	local _, label = Build.billboard({
		Adornee = veil,
		Text = `<b>{string.upper(nextWorld.Name)}</b>`,
		Size = UDim2.fromScale(30, 8),
		Offset = Vector3.new(0, 16, 0),
		Color = nextWorld.Color,
		MaxDistance = 500,
	})
	label.Name = "PortalText"
end

local function buildTrack(world, worldIndex: number, parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = world.Id
	folder.Parent = parent

	local origin = Track.origin(worldIndex)
	local length = Track.length() + 90
	local centerZ = length / 2 - 50

	--[[
		Podlaha po úsecích, ne jedním kusem.

		Každý úsek mezi zdmi patří do zóny (viz `Shared.Zones`) a nese její
		barvu a materiál. Hráč tak vidí postup pod nohama, ne jen v číslech
		— a přechod přes zeď je vstup někam jinam, ne další stejný metr.
	]]
	for index = 0, TRACK.BarrierCount do
		local zone = Zones.at(math.max(index, 1))
		local material = (Enum.Material :: any)[zone.Material] or Enum.Material.Concrete
		-- Barvy levelu obarvené světem; materiál a vzor zůstávají levelu
		local palette = Zones.palette(zone, world)

		--[[
			Deska dráhy sahá až na úroveň terasy.

			Byla čtyři study tlustá, takže mezi jejím spodkem a terasou
			zůstala dvoustudová štěrbina — z terasy bylo vidět pod dráhu.
			Tloušťka se proto počítá z `DeckDrop`: dráha je vyvýšená
			cesta se souvislým bokem, ne deska na neviditelných nohách.
		]]
		local slab = Build.part({
			Name = `Podlaha {zone.Id}`,
			Size = Vector3.new(TRACK.Width, TRACK.DeckDrop, TRACK.SegmentLength),
			Position = origin
				+ Vector3.new(
					0,
					-TRACK.DeckDrop / 2,
					index * TRACK.SegmentLength - TRACK.SegmentLength / 2
				),
			Color = palette.Floor,
			Material = material,
			-- Důlky na vršku: podklad pod dlaždicemi, který je vidět
			-- ve spárách mezi nimi
			TopSurface = Enum.SurfaceType.Inlet,
			Parent = folder,
		})
		slab.Reflectance = zone.Reflectance
		slab.Transparency = zone.Transparency

		-- Světlý lem po okrajích úseku: hranice zón je tím vidět už z dálky
		for _, side in { -1, 1 } do
			Build.part({
				Name = "Lem",
				Size = Vector3.new(1.6, 0.3, TRACK.SegmentLength),
				Position = origin
					+ Vector3.new(side * (TRACK.Width / 2 - 0.8), 0.15, index * TRACK.SegmentLength - TRACK.SegmentLength / 2),
				Color = palette.Edge,
				Material = Enum.Material.Neon,
				Transparency = 0.35,
				CanCollide = false,
				CastShadow = false,
				Parent = folder,
			})
		end
	end

	--[[
		Příčné pásy v podlaze. Jednolitá plocha rychlost neukáže — oko
		nemá čeho se chytit. Pás každých pár metrů udělá z běhu pohyb.
	]]
	local stripeCount = math.floor(length / 20)
	for index = 0, stripeCount do
		--[[
			Prahy začínají až za startovní plošinou. Ta je vysoká dva study
			a sahá od -46 do -2; práh ve výšce 0,08 by v ní byl pohřbený,
			takže by nebyl vidět a ještě by se s ní pral o pixely.
		]]
		if index * 20 - 40 < 2 then
			continue
		end

		-- Práh nese barvu zóny, ve které leží, ne barvu celého světa
		local zone = Zones.at(math.clamp((index * 20) // TRACK.SegmentLength + 1, 1, TRACK.BarrierCount))

		local band = Build.part({
			Name = "Práh",
			Size = Vector3.new(TRACK.Width - 6, 0.14, 1.6),
			Position = origin + Vector3.new(0, 0.08, index * 20 - 40),
			Color = Zones.palette(zone, world).Edge,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
			Parent = folder,
		})
		-- Každý čtvrtý výraznější, aby vznikl takt, ne jen mřížka
		band.Transparency = if index % 4 == 0 then 0.35 else 0.82
	end

	--[[
		Zábradlí u dráhy místo vysoké zdi.

		Nejdřív to byly šestadvacet studů vysoké neprůhledné stěny, takže
		z dráhy nebylo vidět nikam. Pak z nich bylo zábradlí do sedmi
		studů — jenže pořád jako jeden plný díl na stranu.

		A to je ta plocha, kterou má hráč po celý běh nejblíž u oka:
		tisíc studů dlouhý pás jedné barvy, který zakrývá spodních sedm
		studů výhledu do haly. Zábradlí, které se nedá prohlédnout, není
		zábradlí, je to nízká zeď.

		Teď je z toho skutečné zábradlí: **sloupky** ve svislém rytmu
		a jedno **madlo** přes celou délku. Mezi sloupky je vidět skrz,
		takže hala začíná u nohou, ne až nad hlavou — a hráč má o čem
		poznat rychlost.

		Sloupky se střídají v barvě světa a jeho akcentu. Jeden odstín na
		padesát sloupků by z rytmu udělal tapetu.
	]]
	local POST_STEP = 30

	for _, side in { -1, 1 } do
		local across = side * (TRACK.Width / 2 + 1)

		--[[
			Madlo. Jeden díl přes celou délku: nahoře se stejně dotýká
			sousedního, takže sto kusů by vypadalo úplně stejně.
		]]
		Build.part({
			Name = "Madlo",
			Size = Vector3.new(3.6, 1.4, length),
			Position = origin + Vector3.new(across, TRACK.WallHeight - 1.7, centerZ),
			Color = world.Accent:Lerp(Config.Theme.Ink, 0.15),
			Material = Enum.Material.SmoothPlastic,
			Surface = Enum.SurfaceType.Studs,
			Reflectance = 0.1,
			Parent = folder,
		})

		local posts = math.floor(length / POST_STEP)
		for index = 0, posts do
			local z = centerZ - length / 2 + 12 + index * POST_STEP
			if z > centerZ + length / 2 - 6 then
				break
			end

			Build.part({
				-- Ne "Zeď": zábrana i staré testy hledaly zeď podle jména
				Name = "Sloupek zábradlí",
				Size = Vector3.new(2.6, TRACK.WallHeight - 1, 2.6),
				Position = origin + Vector3.new(across, (TRACK.WallHeight - 1) / 2 - 1, z),
				Color = if index % 2 == 0 then world.Accent else world.Color,
				Material = Enum.Material.Plastic,
				Surface = Enum.SurfaceType.Studs,
				Parent = folder,
			})
		end

		--[[
			Nízká plná lišta u paty zábradlí.

			Mezi sloupky je vidět skrz — což je celý smysl — ale úplně
			prázdná mezera u země vypadá, jako by dráha končila do
			vzduchu. Lišta ji uzavře, a přitom je tak nízká, že výhled
			nebere.
		]]
		Build.part({
			Name = "Lišta zábradlí",
			Size = Vector3.new(3, 2.2, length),
			Position = origin + Vector3.new(across, 0.1, centerZ),
			Color = Config.Theme.Panel,
			Material = Enum.Material.Plastic,
			Surface = Enum.SurfaceType.Studs,
			Parent = folder,
		})

		--[[
			Neviditelná zábrana nad zábradlím.

			Zábradlí je sedm studů vysoké, aby přes ně bylo vidět do haly.
			Jenže postava v Robloxu doskočí na sedm a půl — takže se dalo
			přeskočit, seskočit na terasu a **obejít každou zeď**. Celý
			postup hrou se tím dal přeskákat a nikdo by si toho nemusel
			všimnout, protože se to nikde neprojeví jako chyba, jen jako
			hráč s podezřele vysokým skóre.

			Zábrana je průhledná a nedotazovatelná: hráče zastaví, ale
			nic ji nevidí ani po ní nestřílí paprsky.

			Sahá až k zemi, ne až od madla. Zábradlí je od té doby, co má
			sloupky, průhledné i průchozí — mezi sloupky je mezera, kterou
			se dá projít na terasu a obejít každou zeď. Zábrana musí být
			souvislá právě proto, že to viditelné zábradlí souvislé není.
		]]
		local fence = Build.part({
			Name = "Zábrana",
			Size = Vector3.new(2, 33, length),
			Position = origin
				+ Vector3.new(side * (TRACK.Width / 2 + 1), TRACK.WallHeight + 8.5, centerZ),
			Color = Config.Theme.Panel,
			Material = Enum.Material.SmoothPlastic,
			Transparency = 1,
			CastShadow = false,
			Parent = folder,
		})
		fence.CanCollide = true

		local strip = Build.part({
			Name = "Pás",
			Size = Vector3.new(0.6, 1, length),
			Position = origin + Vector3.new(side * (TRACK.Width / 2 - 0.4), 1.4, centerZ),
			Color = world.Accent,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
			Parent = folder,
		})
		strip.Transparency = 0.15
	end

	buildHall(world, origin, length, centerZ, folder)

	buildStart(world, worldIndex, folder)
	buildFinish(world, worldIndex, folder)
	buildPortal(worldIndex, folder)
	buildRibs(world, origin, length, folder)
	buildPads(world, worldIndex, folder)
	buildBouncers(world, worldIndex, folder)
	buildPhysics(world, worldIndex, folder)
	buildDrift(world, origin, length, folder)
	buildProps(world, worldIndex, folder)

	for index = 1, TRACK.BarrierCount do
		buildBarrierFrame(world, worldIndex, index, folder)

		local z = Track.barrierPosition(worldIndex, index).Z - origin.Z
		buildArch(world, origin, z, folder)
		buildZoneSign(world, worldIndex, index, folder)
		buildDecor(Zones.at(index), worldIndex, index, folder)
		buildGiant(Zones.at(index), worldIndex, index, folder)
		-- Sloup do půlky mezi tuhle a další bariéru
		buildPillars(world, origin, z + TRACK.SegmentLength / 2, folder)
	end

	return folder
end

function WorldService.build()
	buildLighting()

	local existing = Workspace:FindFirstChild("Worlds")
	if existing then
		existing:Destroy()
	end

	local root = Instance.new("Folder")
	root.Name = "Worlds"
	root.Parent = Workspace

	for index, world in Config.Worlds do
		buildTrack(world, index, root)
	end

	-- Hráči se do světů teleportují ručně; výchozí spawn ať je u prvního
	local spawnLocation = Workspace:FindFirstChildOfClass("SpawnLocation")
	if spawnLocation then
		spawnLocation:Destroy()
	end

	local spawnPad = Instance.new("SpawnLocation")
	spawnPad.Name = "Spawn"
	spawnPad.Size = Vector3.new(10, 1, 10)
	spawnPad.CFrame = Track.spawnCFrame(1)
	spawnPad.Anchored = true
	spawnPad.Transparency = 1
	spawnPad.CanCollide = false
	spawnPad.Duration = 0
	spawnPad.Neutral = true
	spawnPad.Parent = root

	return root
end

return WorldService

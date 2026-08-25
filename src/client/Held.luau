--!strict
--[[
	Held — squishy hračka v ruce.

	Tohle je ta věc, kterou hráč vidí celou dobu uprostřed obrazu.
	Hračka je v ruce a dá se s ní mačkat, takže je součástí hraní,
	ne řádkem ve statistice.

	Modul dělá tři věci:

	  1. **Drží** hračku v pravé ruce (a další na pásku) svarem, takže
	     jede s animací postavy, ne vedle ní.
	  2. **Mačká** ji — pomalý návrat přes `Squish`, k tomu zvuk a
	     zmenšení postavy o kousek, aby to vypadalo jako pohyb celého
	     těla a ne jen dílu.
	  3. **Dýchá** — i když se nic neděje, hračka se sotva znatelně
	     nafukuje. Nehybný díl v ruce vypadá jako chyba vykreslování.

	Vlastní hodnotu zmáčknutí modul nepočítá. Klient jen řekne serveru
	"zmáčkl jsem" a Power přijde zpátky — cokoliv jiného by byl
	nejlevnější exploit ve hře.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Build = require(Shared.Build)
local Live = require(Shared.Live)
local Remotes = require(Shared.Remotes)
local Toy = require(Shared.Toy)

local Squish = require(script.Parent.Squish)
local SoundKit = require(script.Parent.SoundKit)

local player = Players.LocalPlayer

local Held = {}

--[[
	Držená hračka. `Pieces` jsou všechny kusy (tělo, díry, obal),
	`Root` je ten největší — na něm visí zvuk a jiskřičky a podle něj
	se počítá, jak daleko od dolíku který kus je.
]]
type Toy = {
	Id: string,
	Root: BasePart,
	Pieces: { BasePart },
	-- Původní velikost každého kusu; dýchání ji přepisuje a bez
	-- zapamatování by se hračka po pár nádeších trvale scvrkla
	Bases: { [BasePart]: Vector3 },
	Nominal: number,
}

local toys: { Toy } = {}
local heldIds: { string } = {}
local elapsed = 0
local lowGraphics = false
local lastSqueezeAt = 0
local squeezeCount = 0

--[[
	Nejrychlejší tempo, které klient pustí dál. Server má vlastní strop
	(`Live.SqueezeRate`); tenhle je o kousek volnější schválně — hráč
	nemá vidět, že mu hra zahazuje stisky, jen že rychlejší mačkání už
	nic nepřidá.
]]
local MIN_GAP = 1 / (Live.SqueezeRate + 2)

local function shapeOf(shape: string): Enum.PartType
	if shape == "Ball" then
		return Enum.PartType.Ball
	elseif shape == "Cylinder" then
		return Enum.PartType.Cylinder
	end
	return Enum.PartType.Block
end

--[[
	Kam který kus patří.

	Slot 1 je ruka. Zbytek visí u pasu po stranách — hráč tak vidí, že
	má u sebe víc věcí, ale pořád je jasné, se kterou se dá mačkat.
]]
local function mountFor(character: Model, slot: number): (BasePart?, CFrame)
	if slot == 1 then
		local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
		if hand then
			return hand :: BasePart, CFrame.new(0, -1.1, -0.2)
		end
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil, CFrame.identity
	end

	-- Sudé doprava, liché doleva, každé další o kousek dozadu
	local side = if slot % 2 == 0 then 1 else -1
	local depth = math.floor((slot - 2) / 2) * 0.5
	return root :: BasePart, CFrame.new(side * 1.4, -0.6, 0.5 + depth)
end

local function clear()
	for _, toy in toys do
		for _, piece in toy.Pieces do
			piece:Destroy()
		end
	end
	table.clear(toys)
end

function Held.clear()
	clear()
	table.clear(heldIds)
end

--[[
	Nápis na kusu.

	Máslo má na obalu modrý text a je to ta věc, podle které ho člověk
	na první pohled pozná. Nahrávat kvůli tomu obrázek by znamenalo
	asset navíc — SurfaceGui s textem udělá to samé a funguje i v hře,
	která nemá nahraný jediný soubor.
]]
local function applyLabel(piece: BasePart, label)
	local face = (Enum.NormalId :: any)[label.Face] or Enum.NormalId.Front

	local surface = Instance.new("SurfaceGui")
	surface.Face = face
	surface.CanvasSize = Vector2.new(200, 120)
	surface.LightInfluence = 0.6
	surface.Adornee = piece
	surface.Parent = piece

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(0.86, 0.7)
	text.Position = UDim2.fromScale(0.07, 0.15)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.LuckiestGuy
	text.TextScaled = true
	text.TextColor3 = label.Color
	text.Text = label.Text
	text.Rotation = label.Rotation or 0
	text.Parent = surface
end

--[[
	Postaví jednu hračku podle receptu z `Shared.Toy`.

	Kusů je pár na hračku, ale hráč jich může držet šest, takže se
	nesváří kus ke kusu: každý visí rovnou na těle postavy vlastním
	svarem. Řetěz svarů by se při každém zmáčknutí přepočítával celý.
]]
local function buildToy(squishy, mount: BasePart, offset: CFrame, nominal: number, parent: Instance): Toy?
	local pieces: { BasePart } = {}
	local bases: { [BasePart]: Vector3 } = {}
	local root: BasePart? = nil
	local biggest = 0

	for index, piece in Toy.pieces(squishy) do
		local size = piece.Size * nominal
		local rotation = piece.Rotation or Vector3.zero

		local part = Build.part({
			Name = `{squishy.Id}_{index}`,
			Shape = shapeOf(piece.Kind),
			Size = size,
			Position = mount.Position,
			Color = Toy.colorFor(piece.Role, squishy.Color, piece.Color),
			--[[
				Matný plast, ne Neon. Squishy hračka je guma; Neon by
				z ní udělal svítící cukrátko a celý ten měkký dojem,
				kvůli kterému tu je, by byl pryč.
			]]
			Material = Enum.Material.SmoothPlastic,
			Reflectance = piece.Reflectance or 0.1,
			Transparency = piece.Transparency or 0,
			CanCollide = false,
			CastShadow = false,
			Anchored = false,
			Parent = parent,
		})

		if piece.Label then
			applyLabel(part, piece.Label)
		end

		local weld = Instance.new("Weld")
		weld.Part0 = mount
		weld.Part1 = part
		weld.C0 = offset
			* CFrame.new(piece.Offset * nominal)
			* CFrame.Angles(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))
		weld.Parent = part

		local volume = size.X * size.Y * size.Z
		if volume > biggest then
			biggest = volume
			root = part
		end

		bases[part] = size
		table.insert(pieces, part)
	end

	if not root then
		return nil
	end

	return { Id = squishy.Id, Root = root, Pieces = pieces, Bases = bases, Nominal = nominal }
end

--[[
	Postaví hračky na postavě. Volá se při každé změně držení i po
	respawnu — porovnávat, co přesně se změnilo, by se u tří hraček
	nevyplatilo.
]]
function Held.rebuild()
	clear()

	if lowGraphics then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	for slot, id in heldIds do
		local squishy = Live.squishy(id)
		if not squishy then
			continue
		end

		local mount, offset = mountFor(character, slot)
		if not mount then
			continue
		end

		local nominal = if slot == 1 then 1.5 else 0.9
		local toy = buildToy(squishy, mount, offset, nominal, character)
		if toy then
			table.insert(toys, toy)
		end
	end
end

function Held.setHeld(ids: { string })
	heldIds = table.clone(ids)
	Held.rebuild()
end

function Held.setLowGraphics(enabled: boolean)
	lowGraphics = enabled
	if enabled then
		clear()
	else
		Held.rebuild()
	end
end

--[[
	Zmáčknutí.

	Hloubka i doba návratu jdou z `Softness` hračky: měkká se propadne
	skoro celá a vrací se dlouho, tvrdá jen cvakne. Právě ten pomalý
	návrat je to, co dělá squishy hračku squishy — ne zvuk.
]]
--[[
	Rozdá promáčknutí po kusech hračky.

	Skutečná squishy hračka se nezplošťuje celá — pod prstem je dolík
	a zbytek se skoro nehne. `origin` je místo dolíku (v podílech
	velikosti hračky), `falloff` říká, jak rychle to ubývá do stran.

	Bez tohohle vypadal i pomalý návrat jako "díl se zmenšil": celý sýr
	se srovnal najednou a díry se srovnaly s ním. Takhle se propadne
	jen roh, kterého se prst dotkl.
]]
local function pressToy(toy: Toy, squishy, origin: Vector3, depth: number, rise: number, hold: number)
	local reach = toy.Nominal * 1.1

	for _, piece in toy.Pieces do
		if not piece.Parent then
			continue
		end

		local weld = piece:FindFirstChildWhichIsA("Weld")
		local at = if weld then weld.C0.Position else Vector3.zero
		local distance = (at - origin * toy.Nominal).Magnitude

		--[[
			Kus daleko od dolíku se pořád trochu hne. Nula by ho nechala
			stát v původní velikosti uprostřed promáčknuté hmoty a
			vypadalo by to, že hračka je uvnitř dutá.
		]]
		local falloff = math.clamp(1 - distance / reach, 0.25, 1)

		Squish.rebase(piece)
		Squish.press(piece, depth * falloff, rise, -Vector3.yAxis, hold)
	end
end

--[[
	Kde se hračky prst dotkne.

	Ne uprostřed: dolík uprostřed vypadá jako lisování, ne jako
	zmáčknutí prstem. Místo se navíc mezi stisky posouvá, takže
	rychlé mačkání nevypadá jako jedna opakovaná animace.
]]
local function fingerSpot(): Vector3
	local wobble = (squeezeCount % 4) / 4
	return Vector3.new(0.18 - wobble * 0.36, 0.34, 0.22)
end

--[[
	Zmáčknutí.

	Hloubka, doba návratu i lepivé přidržení jdou z `Softness` hračky:
	měkká se propadne skoro celá, chvíli u prstu zůstane a vrací se
	dlouho; tvrdá jen cvakne. Právě to přidržení a pomalý návrat dělá
	squishy hračku squishy — ne zvuk.
]]
function Held.squeeze()
	local now = os.clock()
	if now - lastSqueezeAt < MIN_GAP then
		return
	end
	lastSqueezeAt = now

	local toy = toys[1]
	local squishy = if toy then Live.squishy(toy.Id) else nil
	if not toy or not squishy then
		return
	end

	squeezeCount += 1

	pressToy(
		toy,
		squishy,
		fingerSpot(),
		0.35 + squishy.Softness * 0.5,
		-- SUPER slow rise: měkká hračka se vrací skoro celou vteřinu
		0.3 + squishy.Softness * 0.75,
		-- lepivé přidržení jen u těch opravdu měkkých
		math.max(squishy.Softness - 0.6, 0) * 0.3
	)

	--[[
		Výška tónu stoupá se sérií a po pauze spadne zpátky. Stejný trik
		jako u sbírání: mozek to slyší jako postup, i když je to pořád
		ten samý vzorek.
	]]
	local step = math.min(squeezeCount, 12)
	SoundKit.playNamed("Pickup", {
		Position = toy.Root.Position,
		Pitch = 0.8 + step * 0.045 + (1 - squishy.Softness) * 0.4,
		Volume = 0.5,
	})

	Remotes.Squeeze:FireServer()
end

--[[
	Zmáčkne hračku "zvenčí" — nárazem, dopadem, průrazem zdi.

	Hračka v ruce, která reaguje jen na klikání, působí jako přilepený
	kus. Když se zmáčkne i při dopadu na zem a při proražení zdi, čte to
	oko jako měkkou hmotu, která tam opravdu je. Serveru se nic neposílá:
	tohle je čistě to, jak to vypadá, ne příjem.
]]
function Held.nudge(strength: number)
	local toy = toys[1]
	local squishy = if toy then Live.squishy(toy.Id) else nil
	if not toy or not squishy then
		return
	end

	-- Náraz mačká hračku shora celou, ne prstem do rohu, takže je
	-- dolík uprostřed a bez lepivého přidržení
	pressToy(
		toy,
		squishy,
		Vector3.new(0, 0.4, 0),
		math.clamp(strength, 0.1, 0.7) * squishy.Softness,
		0.3 + squishy.Softness * 0.5,
		0
	)
end

--[[
	Krátký záblesk u hračky, když zmáčknutí něco přineslo. Server
	potvrzuje Power zvlášť, takže se tohle pouští až podle něj — jinak
	by hráč viděl odměnu i u stisků, které se zahodily.
]]
function Held.reward(amount: number)
	local toy = toys[1]
	if not toy or lowGraphics or amount <= 0 then
		return
	end

	local part = toy.Root

	local spark = Instance.new("Attachment")
	spark.Parent = part

	local burst = Instance.new("ParticleEmitter")
	burst.Color = ColorSequence.new(part.Color)
	burst.LightEmission = 0.6
	burst.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	burst.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	burst.Lifetime = NumberRange.new(0.2, 0.45)
	burst.Speed = NumberRange.new(4, 10)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Rate = 0
	burst.Parent = spark
	burst:Emit(6)

	Debris:AddItem(spark, 0.6)
end

--[[
	Dýchání. Rozsah je schválně na hranici viditelnosti — jakmile je
	nafukování vidět jako animace, přestane to působit jako hmota
	a začne to působit jako efekt.

	Nesahá se na díl, který zrovna drží `Squish`: ten si velikost
	přepisuje sám a dvě věci najednou by ho nechaly natrvalo zmenšený.
]]
function Held.start()
	RunService.Heartbeat:Connect(function(deltaTime)
		elapsed += deltaTime

		-- Série se po pauze rozpadne, aby tón začínal zase dole
		if os.clock() - lastSqueezeAt > 1.2 then
			squeezeCount = 0
		end

		if #toys == 0 or lowGraphics then
			return
		end

		--[[
			Celá hračka dýchá jedním tempem. Kdyby každý kus dýchal
			po svém, kobliha by se rozsypala na osm nezávisle se
			nafukujících koulí.
		]]
		for index, toy in toys do
			local breath = 1 + math.sin(elapsed * 1.8 + index) * 0.03

			for _, piece in toy.Pieces do
				if not piece.Parent or Squish.isPressed(piece) then
					continue
				end

				local base = toy.Bases[piece]
				if base then
					piece.Size = Vector3.new(base.X * breath, base.Y / breath, base.Z * breath)
				end
			end
		end
	end)

	--[[
		Respawn: postava je nová, svary staré. Bez tohohle by hráč po
		smrti chodil s prázdnou rukou až do další změny držení.
	]]
	player.CharacterAdded:Connect(function()
		task.wait(0.4)
		Held.rebuild()
	end)
end

return Held

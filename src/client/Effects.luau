--!strict
--[[
	Effects — ASMR část hry.

	Když bariéra praskne, musí to být slyšet i vidět: tabule se rozpadne
	na desítky střepů, které odletí, vyletí obláček částic, projede rázová
	vlna, obraz na chvíli cukne a ozve se zvuk laděný podle materiálu světa.

	Zvuky se hrají přes vlastní SoundGroup, aby si je hráč mohl ztlumit
	bez ztlumení celé hry.
]]

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Assets = require(Shared.Assets)
local Build = require(Shared.Build)
local Config = require(Shared.Config)
local Format = require(Shared.Format)

local CameraFX = require(script.Parent.CameraFX)
local Fracture = require(script.Parent.Fracture)
local SoundKit = require(script.Parent.SoundKit)

local Effects = {}

local random = Random.new()

-- Stoupající stupnice pro sbírání: rychle za sebou = tón leze nahoru,
-- po pauze spadne zpátky. Tohle je ten návykový ASMR prvek.
local pickupLadder = SoundKit.ladder(0.65)

--[[
	Nízká grafika. Neškrtá efekty úplně — jen jich dělá míň, protože
	úplně němý průraz by ubral to hlavní, proč se hraje.
]]
local detail = 1

--[[
	Světla ve světě staví server, takže je klient nemůže nepostavit —
	může je ale zhasnout. Na slabém telefonu je dvacet svítících bodů
	v jedné chodbě to první, co sundá snímkovou frekvenci, a Neon
	materiál zůstane vidět i bez nich.

	Přepínač si volbu PAMATUJE a hlídá i světla, která dorazí později.
	Bez toho platil jen na to, co bylo v okamžiku přepnutí načtené —
	tedy na okolí hráče — a zbytek trati se rozsvítil, jakmile k němu
	hráč doběhl. Zrovna u nastavení pro slabá zařízení je to obzvlášť
	nepříjemné: zapne se kvůli výkonu a výkon se stejně po chvíli
	propadne.
]]
local worldLightsOn = true
local watchingLights = false

local function applyLight(instance: Instance)
	if instance:IsA("PointLight") or instance:IsA("SpotLight") then
		instance.Enabled = worldLightsOn
	end
end

local function setWorldLights(enabled: boolean)
	worldLightsOn = enabled

	local worlds = Workspace:FindFirstChild("Worlds")
	if not worlds then
		return
	end

	for _, descendant in worlds:GetDescendants() do
		applyLight(descendant)
	end

	if not watchingLights then
		watchingLights = true
		worlds.DescendantAdded:Connect(applyLight)
	end
end

function Effects.setLowGraphics(enabled: boolean)
	detail = if enabled then 0.3 else 1
	CameraFX.setLowGraphics(enabled)
	setWorldLights(not enabled)
end

-- Otřes kamery řeší CameraFX na pružinách; tohle je jen průchozí volání,
-- aby zbytek kódu nemusel vědět, kdo ho zpracuje.
function Effects.shake(amount: number)
	CameraFX.shake(amount)
end

-- Létající text -------------------------------------------------------------------

function Effects.floatingText(position: Vector3, text: string, color: Color3, scale: number)
	local anchor = Build.part({
		Name = "Popisek",
		Size = Vector3.new(0.2, 0.2, 0.2),
		Position = position + Vector3.new(random:NextNumber(-1.5, 1.5), 1, 0),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
		Parent = Workspace,
	})

	local billboard, label = Build.billboard({
		Adornee = anchor,
		Text = text,
		Size = UDim2.fromScale(7 * scale, 2.4 * scale),
		Color = color,
		AlwaysOnTop = true,
		MaxDistance = 120,
	})
	billboard.Name = "Float"

	local info = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(anchor, info, { CFrame = anchor.CFrame + Vector3.new(0, 7, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1 }):Play()

	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, info, { Transparency = 1 }):Play()
	end

	Debris:AddItem(anchor, 1)
end

-- Sebrání pickupu --------------------------------------------------------------------

--[[
	Jiskra u sebraného pickupu.

	Sbírání je to, co hráč dělá pořád — a do teď u něj byl jen text.
	Pár částic navíc stojí skoro nic a udělá z toho událost. Při
	rozjetém combu jich je víc, takže je rychlost vidět i tady dole,
	ne jen na kartě v rohu.
]]
local function spark(position: Vector3, color: Color3, count: number)
	if detail < 0.5 then
		return
	end

	local emitter = Build.part({
		Name = "Jiskra",
		Size = Vector3.new(0.2, 0.2, 0.2),
		Position = position,
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
		Parent = Workspace,
	})

	local attachment = Instance.new("Attachment")
	attachment.Parent = emitter

	local particles = Instance.new("ParticleEmitter")
	particles.Color = ColorSequence.new(color)
	particles.LightEmission = 1
	particles.LightInfluence = 0
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 0),
	})
	particles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	particles.Lifetime = NumberRange.new(0.2, 0.45)
	particles.Speed = NumberRange.new(6, 16)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.Acceleration = Vector3.new(0, -24, 0)
	particles.Drag = 3
	particles.Rate = 0
	particles.Parent = attachment

	particles:Emit(count)
	Debris:AddItem(emitter, 0.8)
end

--[[
	`chain` je aktuální řetěz comba. Nepoužívá se na hodnotu (tu počítá
	server), ale na porci efektu — vyšší řetěz znamená víc jisker
	a větší text, takže hráč vidí, že se něco děje, i když se nedívá
	na kartu v rohu.
]]
function Effects.pickup(position: Vector3, amount: number, isCrit: boolean, chain: number?)
	local color = if isCrit then Config.Theme.Accent else Config.Theme.Power
	local heat = math.clamp((chain or 0) / 60, 0, 1)

	if isCrit then
		SoundKit.playNamed("Lucky", { Position = position })
	else
		SoundKit.playNamed("Pickup", { Position = position, Pitch = pickupLadder:next(os.clock()) })
	end

	Effects.floatingText(
		position,
		if isCrit then `+{Format.short(amount)}!` else `+{Format.short(amount)}`,
		color,
		(if isCrit then 1.1 else 0.7) * (1 + heat * 0.5)
	)

	spark(position, color, math.floor((if isCrit then 14 else 5) * (1 + heat) * detail))

	if isCrit then
		Effects.shake(0.08)
	end
end

-- Rozpad bariéry ---------------------------------------------------------------------

local function burst(position: Vector3, color: Color3, count: number, power: number)
	local emitter = Build.part({
		Name = "Efekt",
		Size = Vector3.new(0.2, 0.2, 0.2),
		Position = position,
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
		Parent = Workspace,
	})

	local attachment = Instance.new("Attachment")
	attachment.Parent = emitter

	local particles = Instance.new("ParticleEmitter")
	--[[
		Rozlet ze zdi je kouř s kusy, ne třpytky. Jiskřičky si nechává
		sbírání pickupů — kdyby oboje vypadalo stejně, přestalo by být
		poznat, co se právě stalo.
	]]
	Assets.particle(particles, "Smoke")
	particles.Color = ColorSequence.new(color)
	particles.LightEmission = 0.7
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.6 * power),
		NumberSequenceKeypoint.new(1, 0),
	})
	particles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	particles.Lifetime = NumberRange.new(0.4, 0.9)
	particles.Speed = NumberRange.new(14 * power, 34 * power)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.Rotation = NumberRange.new(0, 360)
	particles.RotSpeed = NumberRange.new(-240, 240)
	particles.Acceleration = Vector3.new(0, -46, 0)
	particles.Parent = attachment

	particles:Emit(count)
	Debris:AddItem(emitter, 1.4)
end

--[[
	Zaseknutí při nárazu (hitstop).

	Roblox engine pozastavit nejde, ale o to ani nejde: co dělá náraz
	„hmotným" je, že se hráč na okamžik NEHNE. Stačí tedy na pár setin
	sekundy vynulovat rychlost chůze.

	Dvě věci na tom můžou selhat a obě jsou ošetřené:
	  * dva průrazy hned po sobě — proto generace, obnoví jen ta poslední,
	  * respawn během zaseknutí — proto se obnovuje na hodnotu z profilu,
	    ne na tu, kterou jsme si zapamatovali z jiné postavy.

	Když se rychlost nedá zjistit, hitstop se přeskočí. Zaseknutá postava
	je horší vada než chybějící efekt.
]]
local hitstopGeneration = 0
local walkSpeedSource: (() -> number)? = nil

-- Klient dodá funkci, která vrací aktuální povolenou rychlost z profilu.
function Effects.setWalkSpeedSource(source: () -> number)
	walkSpeedSource = source
end

function Effects.hitstop(seconds: number)
	local source = walkSpeedSource
	if not source then
		return
	end

	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	hitstopGeneration += 1
	local generation = hitstopGeneration
	humanoid.WalkSpeed = 0

	task.delay(seconds, function()
		if generation ~= hitstopGeneration then
			return
		end

		local current = Players.LocalPlayer.Character
		local live = current and current:FindFirstChildOfClass("Humanoid")
		if live then
			live.WalkSpeed = source()
		end
	end)
end

--[[
	Hlavní efekt hry: rozbití bariéry.

	`Impact` a `Momentum` nejsou kosmetika — z nich se počítá, kterým
	směrem a jak daleko každý kus odletí. Průraz v běhu proto vypadá
	jinak než průraz z místa.

	`IsLocal` rozhoduje o porci: vlastní průraz dostane plný otřes, zvuk
	a záblesk, cizí jen tišší ozvěnu, aby se z chodby nestala kakofonie.
]]
function Effects.smash(options: {
	CFrame: CFrame,
	Size: Vector3,
	World: any,
	Payload: any,
	IsLocal: boolean,
	Impact: Vector3?,
	Momentum: Vector3?,
	-- Id zóny (Assets.Terrain); přidá k průrazu zvuk materiálu, na kterém stojí
	Zone: string?,
})
	local world = options.World
	local isLocal = options.IsLocal
	local power = if isLocal then 1 else 0.6
	local center = options.CFrame.Position

	Fracture.shatter({
		CFrame = options.CFrame,
		Size = options.Size,
		Color = world.Color,
		Material = world.Material,
		Impact = options.Impact or center,
		Momentum = options.Momentum or Vector3.zero,
		Power = power,
		Detail = detail,
	})

	burst(center, world.Color, math.max(math.floor(70 * power * detail), 8), power)

	-- Rázová vlna dosáhne i na střepy z předchozích průrazů
	if isLocal then
		Fracture.shockwave(center, 34, 42)
	end

	local wave = Build.part({
		Name = "Vlna",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(3, 3, 3),
		Position = center,
		Color = world.Accent,
		Material = Enum.Material.Neon,
		Transparency = 0.4,
		CanCollide = false,
		CastShadow = false,
		Parent = Workspace,
	})
	TweenService:Create(wave, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(52, 52, 52) * power,
		Transparency = 1,
	}):Play()
	Debris:AddItem(wave, 0.5)

	--[[
		Průraz zní ze dvou receptů naráz: světa (sklo, čokoláda, neon) a
		zóny, ve které zeď stojí (želé, marshmallow, kov…).

		Vrstvit je, místo aby jeden nahradil druhý, je celý smysl: svět dá
		zvuku barvu, zóna hmotu. Tatáž skleněná zeď proto v marshmallow
		žuchne a v chromu zazvoní.
	]]
	local volume = if isLocal then 1 else 0.3

	SoundKit.play(Assets.smashRecipe(world.Id), {
		Position = center,
		Volume = volume * 0.75,
	})

	if options.Zone then
		SoundKit.play(Assets.terrain(options.Zone, "Smash"), {
			Position = center,
			Volume = volume,
		})
	end

	if isLocal then
		local payload = options.Payload
		-- Poslední zdi kola dostanou víc: dojezd má být cítit jako dojezd,
		-- ne jako dvanáctý stejný průraz v řadě.
		local left = payload.Left or 99
		local finale = if left <= 2 then 1 + (3 - left) * 0.35 else 1

		--[[
			Šťastná zeď musí být cítit, ne jen spočítaná. Nepravidelná
			odměna drží pozornost jedině tehdy, když si jí hráč všimne —
			a částka, která jen o něco povyskočí, se v tom toku čísel
			ztratí. Proto stejná dávka jako u dojezdu kola.
		]]
		if payload.Jackpot then
			finale = math.max(finale, 1.8)
		end

		-- Podklad se na okamžik stáhne, aby měl náraz prostor
		SoundKit.duck(0.7, 0.18)

		-- Náklon podle toho, z které strany hráč do desky vjel
		local offset = if options.Impact then (options.Impact - center) else Vector3.zero
		local side = math.sign(options.CFrame.RightVector:Dot(offset))
		CameraFX.kick(1 * finale, if side == 0 then 1 else -side)
		CameraFX.flash(0.8 * finale, world.Accent)
		Effects.hitstop(0.05 + (finale - 1) * 0.03)

		if payload.Jackpot then
			Effects.floatingText(
				center + Vector3.new(0, 9, 0),
				"🍀 LUCKY WALL!",
				Config.Theme.Coins,
				1.9
			)
			SoundKit.playNamed("Lucky", { Position = center })
		end

		Effects.floatingText(center + Vector3.new(0, 4, 0), `+{Format.short(payload.Coins)} 💰`, Config.Theme.Coins, 1.5 * finale)
		if payload.Gems and payload.Gems > 0 then
			Effects.floatingText(center + Vector3.new(3, 7, 0), `+{payload.Gems} 💎`, Config.Theme.Gems, 1.1)
		end

		--[[
			Přeplácnutí se ukazuje, až když za to opravdu něco je. Psát
			"×1.1" u každé zdi by z toho udělalo šum, ze kterého se nedá
			nic vyčíst — a hráč se právě tohle má naučit.
		]]
		if payload.Overkill and payload.Overkill >= 1.5 then
			Effects.floatingText(
				center + Vector3.new(-3, 6, 0),
				-- Násobek, ne částka: bez křížku to čte oko jako počet mincí
				`{Format.multiplier(payload.Overkill)} OVERKILL`,
				Config.Theme.Acid,
				1 + math.min(payload.Overkill / 12, 0.8)
			)
		end

		if left == 0 then
			Effects.floatingText(center + Vector3.new(0, 11, 0), "LAP COMPLETE!", Config.Theme.Gold, 2.2)
		elseif left <= 2 then
			Effects.floatingText(center + Vector3.new(0, 9, 0), `{left} TO GO`, Config.Theme.Pink, 1.3)
		end
	end
end

-- Odražení od bariéry, na kterou hráč nemá dost Poweru
function Effects.blocked(position: Vector3, missing: number, world)
	SoundKit.playNamed("Blocked", { Position = position })
	Effects.floatingText(
		position + Vector3.new(0, 3, 0),
		`NEED {Format.short(missing)} MORE`,
		Config.Theme.Danger,
		1.2
	)
	Effects.shake(0.2)
end

return Effects

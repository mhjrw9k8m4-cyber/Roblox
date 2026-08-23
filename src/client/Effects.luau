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
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Assets = require(Shared.Assets)
local Build = require(Shared.Build)
local Config = require(Shared.Config)
local Format = require(Shared.Format)

local SoundKit = require(script.Parent.SoundKit)

local Effects = {}

local random = Random.new()

-- Stoupající stupnice pro sbírání: rychle za sebou = tón leze nahoru,
-- po pauze spadne zpátky. Tohle je ten návykový ASMR prvek.
local pickupLadder = SoundKit.ladder(0.65)

-- Otřes kamery ------------------------------------------------------------------

local shake = 0

function Effects.shake(amount: number)
	shake = math.min(shake + amount, 2)
end

RunService:BindToRenderStep("Shake", Enum.RenderPriority.Camera.Value + 1, function(deltaTime)
	if shake <= 0.001 then
		return
	end

	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local offset = Vector3.new(random:NextNumber(-1, 1), random:NextNumber(-1, 1), 0) * shake * 0.35
	camera.CFrame = camera.CFrame * CFrame.new(offset)
	shake = math.max(shake - deltaTime * 5, 0)
end)

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

function Effects.pickup(position: Vector3, amount: number, isCrit: boolean)
	local color = if isCrit then Config.Theme.Accent else Config.Theme.Power

	if isCrit then
		SoundKit.playNamed("Lucky", { Position = position })
	else
		SoundKit.playNamed("Pickup", { Position = position, Pitch = pickupLadder:next(os.clock()) })
	end

	Effects.floatingText(
		position,
		if isCrit then `+{Format.short(amount)}!` else `+{Format.short(amount)}`,
		color,
		if isCrit then 1.1 else 0.7
	)

	if isCrit then
		Effects.shake(0.08)
	end
end

-- Rozpad bariéry ---------------------------------------------------------------------

local function shards(position: Vector3, size: Vector3, world, count: number)
	for _ = 1, count do
		local shard = Build.part({
			Name = "Střep",
			Size = Vector3.new(
				random:NextNumber(1.5, 4.5),
				random:NextNumber(1.5, 4.5),
				random:NextNumber(0.3, 0.9)
			),
			Position = position
				+ Vector3.new(
					random:NextNumber(-size.X / 2, size.X / 2),
					random:NextNumber(-size.Y / 2, size.Y / 2),
					0
				),
			Color = world.Color,
			Material = world.Material,
			Transparency = 0.1,
			Anchored = false,
			CanCollide = false,
			CastShadow = false,
			Parent = Workspace,
		})

		shard.AssemblyLinearVelocity = Vector3.new(
			random:NextNumber(-26, 26),
			random:NextNumber(6, 34),
			random:NextNumber(14, 46)
		)
		shard.AssemblyAngularVelocity = Vector3.new(
			random:NextNumber(-16, 16),
			random:NextNumber(-16, 16),
			random:NextNumber(-16, 16)
		)

		TweenService:Create(shard, TweenInfo.new(1.4, Enum.EasingStyle.Linear), { Transparency = 1 }):Play()
		Debris:AddItem(shard, 1.5)
	end
end

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
	Hlavní efekt hry. `isLocal` = bariéru prorazil tenhle hráč, takže dostane
	plnou porci (otřes, hlasitější zvuk, popisek s odměnou). Průrazy ostatních
	jsou tišší, aby se z chodby nestala kakofonie.
]]
function Effects.smash(position: Vector3, size: Vector3, world, payload, isLocal: boolean)
	local power = if isLocal then 1 else 0.6

	shards(position, size, world, if isLocal then 26 else 12)
	burst(position, world.Color, math.floor(70 * power), power)

	-- Rázová vlna
	local wave = Build.part({
		Name = "Vlna",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(3, 3, 3),
		Position = position,
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

	SoundKit.play(Assets.smashRecipe(world.Id), {
		Position = position,
		Volume = if isLocal then 1 else 0.3,
	})

	if isLocal then
		Effects.shake(0.9)
		Effects.floatingText(position + Vector3.new(0, 4, 0), `+{Format.short(payload.Coins)} 💰`, Config.Theme.Coins, 1.5)
		if payload.Gems and payload.Gems > 0 then
			Effects.floatingText(position + Vector3.new(3, 7, 0), `+{payload.Gems} 💎`, Config.Theme.Gems, 1.1)
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

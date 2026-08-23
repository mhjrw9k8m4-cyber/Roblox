--!strict
--[[
	Effects — vizuální a zvuková odezva na ránu.

	Cíl je jediný: aby každé kliknutí bylo příjemné.
	  * odletující plátky materiálu,
	  * záblesk částic v barvě materiálu,
	  * jemný otřes kamery, který sílí s combem,
	  * odskočení objektu,
	  * stoupající text s výdělkem,
	  * zvuk, jehož výška roste s combem (to je ten „satisfying“ pocit).

	Zvuky se hrají přes SoundService s vlastním SoundGroup, takže si
	hráč může ASMR ztlumit bez ztlumení celé hry.
]]

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Build = require(Shared.Build)
local Config = require(Shared.Config)
local Format = require(Shared.Format)

local Effects = {}

local random = Random.new()

-- Zvuk -------------------------------------------------------------------

local soundGroup = Instance.new("SoundGroup")
soundGroup.Name = "ASMR"
soundGroup.Volume = 1
soundGroup.Parent = SoundService

-- Přehrané zvuky se recyklují; vytvářet Sound na každou ránu je zbytečný odpad.
local soundPool: { Sound } = {}

local function acquireSound(): Sound
	local sound = table.remove(soundPool)
	if sound then
		return sound
	end

	local created = Instance.new("Sound")
	created.SoundGroup = soundGroup
	created.RollOffMaxDistance = 120
	created.RollOffMode = Enum.RollOffMode.InverseTapered
	created.Parent = SoundService
	return created
end

local function releaseSound(sound: Sound)
	if #soundPool < 24 then
		sound:Stop()
		table.insert(soundPool, sound)
	else
		sound:Destroy()
	end
end

--[[
	Přehraje zvuk. Když se ID nenačte (neplatné nebo cizí audio),
	jen se tiše přeskočí — hra kvůli chybějícímu zvuku nespadne.
]]
function Effects.playSound(soundId: string, pitch: number, volume: number)
	if soundId == "" then
		return
	end

	local sound = acquireSound()
	sound.SoundId = soundId
	sound.PlaybackSpeed = pitch
	sound.Volume = volume

	local ok = pcall(function()
		sound:Play()
	end)

	if not ok then
		releaseSound(sound)
		return
	end

	task.delay(3, releaseSound, sound)
end

-- Otřes kamery ------------------------------------------------------------

local shakeAmount = 0

function Effects.shake(intensity: number)
	shakeAmount = math.min(shakeAmount + intensity, 1.6)
end

RunService:BindToRenderStep("ASMRShake", Enum.RenderPriority.Camera.Value + 1, function(deltaTime)
	if shakeAmount <= 0.001 then
		return
	end

	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local offset = Vector3.new(
		random:NextNumber(-1, 1),
		random:NextNumber(-1, 1),
		random:NextNumber(-1, 1)
	) * shakeAmount * 0.32

	camera.CFrame = camera.CFrame * CFrame.new(offset)
	-- rychlý doběh, ať se obraz neroztřese natrvalo
	shakeAmount = math.max(shakeAmount - deltaTime * 6, 0)
end)

-- Částice a plátky --------------------------------------------------------

local function burst(position: Vector3, color: Color3, count: number, power: number)
	local emitterPart = Build.part({
		Name = "Efekt",
		Size = Vector3.new(0.2, 0.2, 0.2),
		Position = position,
		Transparency = 1,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		Parent = Workspace,
	})

	local attachment = Instance.new("Attachment")
	attachment.Parent = emitterPart

	local particles = Instance.new("ParticleEmitter")
	particles.Color = ColorSequence.new(color)
	particles.LightEmission = 0.6
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9 * power),
		NumberSequenceKeypoint.new(1, 0),
	})
	particles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	particles.Lifetime = NumberRange.new(0.35, 0.7)
	particles.Speed = NumberRange.new(8 * power, 18 * power)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.Rotation = NumberRange.new(0, 360)
	particles.RotSpeed = NumberRange.new(-220, 220)
	particles.Acceleration = Vector3.new(0, -40, 0)
	particles.Parent = attachment

	particles:Emit(count)
	Debris:AddItem(emitterPart, 1.2)
end

-- Odletující plátek: to nejvíc „satisfying“ na krájení
local function slice(position: Vector3, color: Color3, material: Enum.Material, power: number)
	local part = Build.part({
		Name = "Plátek",
		Size = Vector3.new(random:NextNumber(0.8, 1.8), 0.14, random:NextNumber(0.8, 1.8)) * power,
		Position = position + Vector3.new(0, random:NextNumber(-1, 1), 0),
		Color = color,
		Material = material,
		Anchored = false,
		CanCollide = false,
		CanQuery = false,
		Parent = Workspace,
	})

	part.CanTouch = false
	part.CastShadow = false
	part.AssemblyLinearVelocity = Vector3.new(
		random:NextNumber(-22, 22),
		random:NextNumber(14, 30),
		random:NextNumber(-22, 22)
	) * power
	part.AssemblyAngularVelocity = Vector3.new(
		random:NextNumber(-14, 14),
		random:NextNumber(-14, 14),
		random:NextNumber(-14, 14)
	)

	TweenService:Create(part, TweenInfo.new(1.1, Enum.EasingStyle.Linear), { Transparency = 1 }):Play()
	Debris:AddItem(part, 1.2)
end

-- Stoupající text s výdělkem ----------------------------------------------

local function floatingText(position: Vector3, text: string, color: Color3, scale: number)
	local anchor = Build.part({
		Name = "Popisek",
		Size = Vector3.new(0.2, 0.2, 0.2),
		Position = position + Vector3.new(random:NextNumber(-1.5, 1.5), 1.5, 0),
		Transparency = 1,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		Parent = Workspace,
	})

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(6 * scale, 2 * scale)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 90
	billboard.Adornee = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.TextScaled = true
	label.Parent = billboard

	billboard.Parent = anchor

	local info = TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(anchor, info, { CFrame = anchor.CFrame + Vector3.new(0, 7, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()

	Debris:AddItem(anchor, 1)
end

-- Veřejné efekty ----------------------------------------------------------

--[[
	Rána do materiálu. `isLocal` = ránu udělal tenhle hráč, takže dostane
	plný zážitek (otřes, hlasitější zvuk, popisek s výdělkem).
	Rány ostatních hráčů jsou tišší, ať se hub nezmění v kakofonii.
]]
function Effects.strike(payload, isLocal: boolean)
	local object = Config.object(payload.ObjectId)
	local tool = Config.tool(payload.ToolId)
	if not object then
		return
	end

	local power = if isLocal then 1 else 0.55
	local comboBoost = math.clamp(payload.Multiplier or 1, 1, 4)

	slice(payload.Position, object.Color, object.Material, power)
	burst(payload.Position, object.Color, math.floor(10 * power) + 4, power)

	-- Výška zvuku roste s combem: čím rychleji sekáš, tím líbivější tón
	local pitch = object.Pitch * (0.9 + comboBoost * 0.12) + random:NextNumber(-0.04, 0.04)
	Effects.playSound(object.SoundId, pitch, (if isLocal then 0.55 else 0.18))

	if tool then
		Effects.playSound(tool.SoundId, tool.Pitch * (0.95 + comboBoost * 0.06), (if isLocal then 0.3 else 0.1))
	end

	if isLocal then
		Effects.shake(0.12 * comboBoost)
		floatingText(
			payload.Position,
			`+{Format.short(payload.Coins)}`,
			if payload.Combo >= 10 then Config.Theme.Gold else Config.Theme.Text,
			0.7 + math.min(payload.Combo, 30) * 0.02
		)
	end
end

-- Rozpad materiálu: velký záblesk, kruhová rázová vlna a bonus
function Effects.destroy(payload, isLocal: boolean)
	local object = Config.object(payload.ObjectId)
	if not object then
		return
	end

	local power = if isLocal then 1 else 0.6

	burst(payload.Position, object.Color, math.floor(60 * power), 1.6 * power)
	for _ = 1, math.floor(8 * power) do
		slice(payload.Position, object.Color, object.Material, power)
	end

	-- Rázová vlna
	local wave = Build.part({
		Name = "Vlna",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2, 2, 2),
		Position = payload.Position,
		Color = object.Color,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		Parent = Workspace,
	})
	wave.CastShadow = false

	TweenService:Create(wave, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(26, 26, 26) * power,
		Transparency = 1,
	}):Play()
	Debris:AddItem(wave, 0.6)

	Effects.playSound(object.SoundId, object.Pitch * 0.7, (if isLocal then 0.8 else 0.25))

	if isLocal then
		Effects.shake(0.75)
		floatingText(payload.Position, `+{Format.short(payload.Bonus)} BONUS`, Config.Theme.Gold, 1.4)
	end
end

function Effects.levelUp(level: number)
	local character = game:GetService("Players").LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local camera = Workspace.CurrentCamera
	local position = if root then root.Position elseif camera then camera.CFrame.Position else Vector3.zero

	burst(position, Config.Theme.Accent, 70, 1.4)
	floatingText(position + Vector3.new(0, 3, 0), `ÚROVEŇ {level}!`, Config.Theme.Accent, 1.6)
	Effects.shake(0.5)
end

return Effects

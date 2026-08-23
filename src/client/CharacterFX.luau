--!strict
--[[
	CharacterFX — pohyby postavy bez jediné nahrané animace.

	Nahrané animace by znamenaly cizí `rbxassetid://`, které v cizí hře
	nemusí projít právy. Všechno tady proto běží čistě z kódu:

	  * náklon při běhu     — otočení RootJoint.C0
	  * houpání kamery      — Humanoid.CameraOffset
	  * nabíjecí póza       — ramena dozadu, když je dost Poweru na průraz
	  * odraz při průrazu   — ruce dopředu + protažení postavy
	  * dřep při dopadu     — krátké smáčknutí přes škálování Humanoida
	  * rychlostní čáry     — částice za zády při vysoké rychlosti
	  * stopa               — Trail v barvě světa

	Proč `Motor6D.C0` a ne `Transform`: `Transform` každý snímek přepíše
	Animator, takže by se pózy okamžitě smazaly. `C0` je základní posun
	kloubu, který se s běžící animací sčítá — pózy se tak na výchozí
	animaci navrství, místo aby s ní bojovaly.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Build = require(Shared.Build)
local Config = require(Shared.Config)

local SoundKit = require(script.Parent.SoundKit)

local player = Players.LocalPlayer

local CharacterFX = {}

-- Kloub -> jeho původní C0. Bez toho by se offsety sčítaly donekonečna.
type Joint = {
	Motor: Motor6D,
	Base: CFrame,
}

local character: Model? = nil
local humanoid: Humanoid? = nil
local root: BasePart? = nil
local joints: { [string]: Joint } = {}
local trail: Trail? = nil
local speedLines: ParticleEmitter? = nil

-- Stav animace
local lean = 0
local bob = 0
local charge = 0 -- 0..1, jak blízko je průraz
local recoil = 0 -- doznívající odraz po průrazu
local squash = 0 -- doznívající dřep po dopadu
local elapsed = 0

-- R15 i R6 najednou: R6 má v názvech ramen mezeru.
local JOINT_NAMES = {
	Root = { "RootJoint" },
	LeftArm = { "LeftShoulder", "Left Shoulder" },
	RightArm = { "RightShoulder", "Right Shoulder" },
}

local function findJoint(model: Model, names: { string }): Motor6D?
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") then
			for _, name in names do
				if descendant.Name == name then
					return descendant
				end
			end
		end
	end
	return nil
end

-- Doplňky na postavě -------------------------------------------------------------

local function attachTrail(worldColor: Color3)
	if not character or not root then
		return
	end

	local existing = root:FindFirstChild("FXTrail")
	if existing then
		existing:Destroy()
	end

	local top = Instance.new("Attachment")
	top.Name = "FXTrailTop"
	top.Position = Vector3.new(0, 1.2, 0.4)
	top.Parent = root

	local bottom = Instance.new("Attachment")
	bottom.Name = "FXTrailBottom"
	bottom.Position = Vector3.new(0, -1.2, 0.4)
	bottom.Parent = root

	local created = Instance.new("Trail")
	created.Name = "FXTrail"
	created.Attachment0 = top
	created.Attachment1 = bottom
	created.Color = ColorSequence.new(worldColor)
	created.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	created.Lifetime = 0.5
	created.LightEmission = 0.8
	created.MinLength = 0.2
	created.Parent = root

	trail = created
end

local function attachSpeedLines(worldColor: Color3)
	if not root then
		return
	end

	local existing = root:FindFirstChild("FXSpeed")
	if existing then
		existing:Destroy()
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "FXSpeed"
	attachment.Position = Vector3.new(0, 0, 1.5)
	attachment.Parent = root

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(worldColor)
	emitter.LightEmission = 0.8
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.25, 0.45)
	emitter.Speed = NumberRange.new(10, 22)
	emitter.SpreadAngle = Vector2.new(14, 14)
	emitter.Rate = 0
	emitter.Parent = attachment

	speedLines = emitter
end

-- Napojení na postavu ---------------------------------------------------------------

function CharacterFX.bind(model: Model, worldColor: Color3)
	character = model
	humanoid = model:FindFirstChildOfClass("Humanoid")
	root = model:FindFirstChild("HumanoidRootPart") :: BasePart?

	table.clear(joints)
	for key, names in JOINT_NAMES do
		local motor = findJoint(model, names)
		if motor then
			joints[key] = { Motor = motor, Base = motor.C0 }
		end
	end

	attachTrail(worldColor)
	attachSpeedLines(worldColor)

	lean, bob, recoil, squash = 0, 0, 0, 0

	-- Dopad na zem = krátké smáčknutí. Vestavěný zvuk dopadu doplníme
	-- měkčím ocasem, aby to sedělo k ASMR ladění zbytku hry.
	if humanoid then
		humanoid.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Landed then
				squash = 1
				SoundKit.playNamed("Land")
			end
		end)
	end
end

function CharacterFX.setWorldColor(color: Color3)
	if trail then
		trail.Color = ColorSequence.new(color)
	end
	if speedLines then
		speedLines.Color = ColorSequence.new(color)
	end
end

-- Nabití: 0 = daleko od průrazu, 1 = bariéra je připravená spadnout
function CharacterFX.setCharge(ratio: number)
	charge = math.clamp(ratio, 0, 1)
end

function CharacterFX.smash()
	recoil = 1
end

-- Smyčka -------------------------------------------------------------------------------

local function applyJoints()
	local rootJoint = joints.Root
	if rootJoint then
		-- Náklon dopředu roste s rychlostí, dozadu při nabíjení —
		-- postava se viditelně "opře" do bariéry.
		local tilt = math.rad(lean * 14 - charge * 10)
		local twist = math.sin(elapsed * 9) * math.rad(lean * 3)
		rootJoint.Motor.C0 = rootJoint.Base * CFrame.Angles(tilt, 0, twist)
	end

	-- Ramena: při nabíjení dozadu, při průrazu prudce dopředu
	local swing = math.rad(charge * -35 + recoil * 70)
	local flap = math.sin(elapsed * 11) * math.rad(lean * 8)

	local left = joints.LeftArm
	if left then
		left.Motor.C0 = left.Base * CFrame.Angles(swing + flap, 0, 0)
	end

	local right = joints.RightArm
	if right then
		right.Motor.C0 = right.Base * CFrame.Angles(swing - flap, 0, 0)
	end
end

--[[
	Squash & stretch přes škálování Humanoida.

	Zápis do těchhle hodnot přestavuje celý rig, takže se zapisuje jen
	když se opravdu něco mění. Bez té podmínky by se rig přestavoval
	šedesátkrát za sekundu i ve chvíli, kdy hráč jen stojí.
]]
local function applyBody()
	local hum = humanoid
	if not hum then
		return
	end

	local stretch = 1 + recoil * 0.12 - squash * 0.18
	local fatten = 1 - recoil * 0.06 + squash * 0.12

	local function write(name: string, value: number)
		local scale = hum:FindFirstChild(name) :: NumberValue?
		if scale and math.abs(scale.Value - value) > 0.004 then
			scale.Value = value
		end
	end

	write("BodyHeightScale", stretch)
	write("BodyDepthScale", fatten)
	write("BodyWidthScale", fatten)
end

local function applyCamera(deltaTime: number)
	local hum = humanoid
	if not hum then
		return
	end

	-- Houpání jen při běhu po zemi; ve vzduchu by to bylo na zvracení.
	local grounded = hum.FloorMaterial ~= Enum.Material.Air
	local target = if grounded then lean else 0
	bob += deltaTime * (8 + lean * 6)

	local vertical = math.sin(bob * 2) * 0.16 * target
	local horizontal = math.sin(bob) * 0.1 * target

	hum.CameraOffset = Vector3.new(horizontal, vertical - squash * 0.6, 0)
end

function CharacterFX.start()
	RunService.RenderStepped:Connect(function(deltaTime)
		elapsed += deltaTime

		local hum = humanoid
		if not hum or not hum.Parent then
			return
		end

		-- `lean` je normalizovaná rychlost 0..1 vůči maximu z upgradů,
		-- aby efekty rostly společně s postupem hráče.
		local maxSpeed = 16 + Config.upgrade("Speed").MaxLevel * Config.upgrade("Speed").PerLevel
		local speed = hum.AssemblyLinearVelocity.Magnitude
		local targetLean = math.clamp(speed / maxSpeed, 0, 1)
		lean += (targetLean - lean) * math.min(deltaTime * 8, 1)

		-- Doznívání jednorázových efektů
		recoil = math.max(recoil - deltaTime * 3.2, 0)
		squash = math.max(squash - deltaTime * 4.5, 0)

		applyJoints()
		applyBody()
		applyCamera(deltaTime)

		if speedLines then
			speedLines.Rate = if lean > 0.55 then (lean - 0.55) * 90 else 0
		end
		if trail then
			trail.Enabled = lean > 0.3
		end
	end)
end

--[[
	Nárazová vlna u nohou při průrazu. Je to prstenec, ne koule —
	na zemi čitelnější a nezakryje hráči výhled dopředu.
]]
function CharacterFX.groundBurst(color: Color3)
	if not root then
		return
	end

	local ring = Build.part({
		Name = "Burst",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 4, 4),
		CFrame = CFrame.new(root.Position - Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.3,
		CanCollide = false,
		CastShadow = false,
		Parent = workspace,
	})

	TweenService:Create(
		ring,
		TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.4, 34, 34), Transparency = 1 }
	):Play()
	Debris:AddItem(ring, 0.5)
end

return CharacterFX

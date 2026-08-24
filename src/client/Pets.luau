--!strict
--[[
	Pets — vykreslování petů, kteří lítají za hráčem.

	Pety jsou lokální: server ví, kdo co má nasazené, ale samotné objekty
	staví každý klient sám. Replikovat je ze serveru by při plném serveru
	znamenalo desítky pohyblivých dílů navíc, a přitom je to čistá parádička.

	Pohyb je pružinový, ne přilepený — pet dojíždí za hráčem se zpožděním
	a při zatáčce se rozhoupe. To je to, co dělá rozdíl mezi "objekt visí
	ve vzduchu" a "něco mě doprovází".
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Build = require(Shared.Build)
local Live = require(Shared.Live)

local player = Players.LocalPlayer

local Pets = {}

type Follower = {
	Id: string,
	Part: BasePart,
	Position: Vector3,
	Velocity: Vector3,
	Slot: number,
}

local followers: { Follower } = {}
local folder: Folder? = nil
local elapsed = 0
local lowGraphics = false

local function shapeOf(shape: string): Enum.PartType
	if shape == "Ball" then
		return Enum.PartType.Ball
	elseif shape == "Cylinder" then
		return Enum.PartType.Cylinder
	end
	return Enum.PartType.Block
end

local function ensureFolder(): Folder
	if folder and folder.Parent then
		return folder
	end

	local created = Instance.new("Folder")
	created.Name = "LocalPets"
	created.Parent = Workspace
	folder = created
	return created
end

local function makePet(pet, rarity, slot: number): BasePart
	local part = Build.part({
		Name = pet.Name,
		Shape = shapeOf(pet.Shape),
		Size = Vector3.new(2.2, 2.2, 2.2),
		Position = Vector3.zero,
		Color = rarity.Color,
		Material = Enum.Material.Neon,
		Transparency = 0.05,
		CanCollide = false,
		CastShadow = false,
		Parent = ensureFolder(),
	})

	Build.light(part, rarity.Color, 1.6, 12)

	-- Jmenovka nad petem: hráč musí poznat, co mu lítá za zády
	local _, label = Build.billboard({
		Adornee = part,
		Text = `<b>{pet.Name}</b>`,
		Size = UDim2.fromScale(5, 1.4),
		Offset = Vector3.new(0, 2.2, 0),
		Color = rarity.Color,
		MaxDistance = 60,
	})
	label.TextSize = 14

	-- Vzácnější pety mají stopu, aby byly poznat i v pohybu
	if rarity.Weight <= 10 then
		local top = Instance.new("Attachment")
		top.Position = Vector3.new(0, 0.8, 0)
		top.Parent = part

		local bottom = Instance.new("Attachment")
		bottom.Position = Vector3.new(0, -0.8, 0)
		bottom.Parent = part

		local trail = Instance.new("Trail")
		trail.Attachment0 = top
		trail.Attachment1 = bottom
		trail.Color = ColorSequence.new(rarity.Color)
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.Lifetime = 0.4
		trail.LightEmission = 1
		trail.Parent = part
	end

	return part
end

function Pets.clear()
	if folder then
		folder:Destroy()
		folder = nil
	end
	table.clear(followers)
end

--[[
	Přestaví pety podle profilu. Volá se při každé změně nasazení;
	porovnávat, co se přesně změnilo, by se u tří objektů nevyplatilo.
]]
function Pets.setEquipped(equipped: { string })
	Pets.clear()

	if lowGraphics then
		return
	end

	for slot, petId in equipped do
		local pet = Live.pet(petId)
		if not pet then
			continue
		end

		local rarity = Live.rarity(pet.Rarity)
		table.insert(followers, {
			Id = petId,
			Part = makePet(pet, rarity, slot),
			Position = Vector3.zero,
			Velocity = Vector3.zero,
			Slot = slot,
		})
	end
end

function Pets.setLowGraphics(enabled: boolean, equipped: { string }?)
	lowGraphics = enabled
	if enabled then
		Pets.clear()
	elseif equipped then
		Pets.setEquipped(equipped)
	end
end

-- Animace líhnutí: pet vyletí z místa hráče a zapadne do formace
function Pets.playHatch(payload)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local rarity = Live.rarity(payload.Rarity)

	local shell = Build.part({
		Name = "Egg",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(3.4, 4.2, 3.4),
		Position = root.Position + Vector3.new(0, 4, 0),
		Color = payload.Color or rarity.Color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
		Parent = Workspace,
	})

	TweenService:Create(shell, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = Vector3.new(6, 7.5, 6),
		Transparency = 1,
	}):Play()
	Debris:AddItem(shell, 0.6)

	local attachment = Instance.new("Attachment")
	attachment.Parent = shell

	local burst = Instance.new("ParticleEmitter")
	burst.Color = ColorSequence.new(rarity.Color)
	burst.LightEmission = 1
	burst.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.4),
		NumberSequenceKeypoint.new(1, 0),
	})
	burst.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	burst.Lifetime = NumberRange.new(0.5, 1)
	burst.Speed = NumberRange.new(16, 34)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Acceleration = Vector3.new(0, -30, 0)
	burst.Parent = attachment
	burst:Emit(rarity.Weight <= 2.4 and 140 or 60)
end

--[[
	Formace: pety létají za hráčem v řadě, každý o kus dál a s vlastní
	fází houpání, aby se nepřekrývali.
]]
local function targetFor(root: BasePart, slot: number, count: number): Vector3
	local spread = (slot - (count + 1) / 2) * 3.2
	local back = root.CFrame.LookVector * -4.5
	local side = root.CFrame.RightVector * spread
	local lift = Vector3.new(0, 3 + math.sin(elapsed * 2 + slot) * 0.5, 0)
	return root.Position + back + side + lift
end

function Pets.start()
	RunService.Heartbeat:Connect(function(deltaTime)
		elapsed += deltaTime

		if #followers == 0 then
			return
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return
		end

		-- Pružina s tlumením: pet dojíždí za cílem místo aby na něm visel
		local stiffness = 90
		local damping = 14
		local step = math.min(deltaTime, 1 / 30)

		for _, follower in followers do
			local target = targetFor(root, follower.Slot, #followers)

			if follower.Position.Magnitude == 0 then
				follower.Position = target
			end

			local toTarget = target - follower.Position
			follower.Velocity += (toTarget * stiffness - follower.Velocity * damping) * step
			follower.Position += follower.Velocity * step

			follower.Part.CFrame = CFrame.new(follower.Position)
				* CFrame.Angles(0, elapsed * 1.4 + follower.Slot, math.rad(12))
		end
	end)
end

return Pets

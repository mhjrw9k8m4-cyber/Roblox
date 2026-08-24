--!strict
--[[
	TrackView — pickupy a prorazitelné tabule, stavěné lokálně.

	Proč lokálně: bariéra musí blokovat každého hráče podle jeho vlastního
	postupu a sebraný pickup musí zmizet jen tomu, kdo ho sebral. Sdílená
	geometrie by to neuměla — díl vytvořený na klientovi existuje jen u něj,
	takže jeho fyzika i viditelnost jsou automaticky "per hráč".

	Server na to samozřejmě nespoléhá: každý sebraný pickup i každý průraz
	si znovu ověří podle vlastních čísel (viz GameService).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Build = require(Shared.Build)
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Track = require(Shared.Track)

local CharacterFX = require(script.Parent.CharacterFX)
local Effects = require(script.Parent.Effects)
local SoundKit = require(script.Parent.SoundKit)
local Textures = require(script.Parent.Textures)

local TRACK = Config.Track
local player = Players.LocalPlayer

local TrackView = {}
TrackView.__index = TrackView

export type Handle = typeof(setmetatable({} :: any, TrackView))

type Pickup = {
	Index: number,
	Part: BasePart,
	Position: Vector3,
	ReadyAt: number,
	-- Když je nastaveno, pickup právě letí k hráči
	Flying: number?,
	FlyFrom: Vector3?,
}

type Barrier = {
	Index: number,
	Part: BasePart,
	Label: TextLabel,
	Required: number,
	-- Kolik prasklin už je vidět; roste s nabitím
	Cracks: number,
	CrackParts: { BasePart },
}

function TrackView.new(): Handle
	local self = setmetatable({}, TrackView)

	self.Folder = nil :: Folder?
	self.Pickups = {} :: { [number]: Pickup }
	self.Barriers = {} :: { [number]: Barrier }
	self.WorldIndex = 0
	self.World = Config.Worlds[1]
	self.Power = 0
	self.Barrier = 1
	self.PickupValue = 1
	self.CollectRadius = TRACK.CollectRadius

	self.WasReady = false
	self.PendingCollects = {} :: { number }
	self.LastSendAt = 0
	self.LastSmashAt = 0
	self.LastBlockedAt = 0

	return self
end

-- Stavba -----------------------------------------------------------------------

local function makePickup(world, position: Vector3, parent: Instance): BasePart
	local part = Build.part({
		Name = "Pickup",
		Size = Vector3.new(2.4, 2.4, 2.4),
		Position = position,
		Color = Config.Theme.Power,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
		Parent = parent,
	})

	Build.billboard({
		Adornee = part,
		Text = "<b>+1</b>",
		Size = UDim2.fromScale(4, 1.6),
		Offset = Vector3.new(0, 2.4, 0),
		Color = Config.Theme.Text,
		MaxDistance = 90,
	})

	return part
end

local function makeBarrier(
	world,
	worldIndex: number,
	index: number,
	parent: Instance,
	chargeOf: (number) -> number
): (BasePart, TextLabel)
	local position = Track.barrierPosition(worldIndex, index)

	local part = Build.part({
		Name = `Barrier{index}`,
		Size = Vector3.new(TRACK.Width - 4, 20, 2.4),
		Position = position + Vector3.new(0, 4, 0),
		Color = world.Color,
		Material = world.Material,
		Transparency = 0.25,
		CanCollide = true,
		CastShadow = false,
		Parent = parent,
	})

	-- Proudící energie napříč tabulí. Beam nepotřebuje obrázek, takže
	-- tohle funguje i bez jediného nahraného assetu.
	Textures.energyField(part, world, 7)

	-- Volitelná textura navrch, když si ji hráč doplní do Assets
	Textures.scroll(part, Enum.NormalId.Front, {
		Asset = Textures.assetFor("Barrier"),
		Color = world.Accent,
		StudsPerTile = 6,
		SpeedV = 4,
		Transparency = 0.35,
	})

	-- Pulz zrychluje, jak se hráč blíží k proražení
	Textures.charge(part, world.Color, world.Accent, function()
		return 3 + chargeOf(index) * 14
	end)

	local _, label = Build.billboard({
		Adornee = part,
		Text = "",
		Size = UDim2.fromScale(18, 5),
		Offset = Vector3.new(0, 13, 0),
		Color = Config.Theme.Text,
		AlwaysOnTop = true,
		MaxDistance = 260,
	})

	return part, label
end

function TrackView:build(worldIndex: number)
	self:clear()

	self.WorldIndex = worldIndex
	self.World = Config.Worlds[worldIndex] or Config.Worlds[1]

	local folder = Instance.new("Folder")
	folder.Name = "LocalTrack"
	folder.Parent = Workspace
	self.Folder = folder

	for index = 1, Track.PickupCount do
		local position = Track.pickupPosition(worldIndex, index)
		if position then
			self.Pickups[index] = {
				Index = index,
				Part = makePickup(self.World, position, folder),
				Position = position,
				ReadyAt = 0,
			}
		end
	end

	-- Pruhy tekoucí po podlaze ukazují, kam běžet
	Textures.flowStripes(
		folder,
		Track.origin(worldIndex) + Vector3.new(0, 0, -20),
		Track.length(),
		self.World,
		14,
		26
	)

	for index = 1, TRACK.BarrierCount do
		local part, label = makeBarrier(self.World, worldIndex, index, folder, function(barrierIndex)
			return self:chargeRatio(barrierIndex)
		end)
		self.Barriers[index] = {
			Index = index,
			Part = part,
			Label = label,
			Required = Config.barrierPower(worldIndex, index),
			Cracks = 0,
			CrackParts = {},
		}
	end

	self:syncBarriers()
end

--[[
	Jak blízko je bariéra k proražení (0..1), nebo nil u neaktivních —
	těm barvu řídí syncBarriers a pulz by jim ji přepisoval.
]]
function TrackView:chargeRatio(index: number): number?
	if index ~= self.Barrier then
		return nil
	end
	local barrier = self.Barriers[index]
	if not barrier then
		return nil
	end
	return math.clamp(self.Power / math.max(barrier.Required, 1), 0, 1)
end

--[[
	Praskliny. Přibývají po krocích, jak Power roste — hráč tak vidí,
	jak blízko je k proražení, i když se nedívá na lištu.

	Kreslí se z tenkých tmavých dílů rozbíhajících se od středu. Textura
	by byla hezčí, ale generovat ji za běhu jde jen s ověřeným účtem,
	takže by se na většině hráčů nezobrazila vůbec.
]]
local CRACK_STEPS = { 0.3, 0.5, 0.7, 0.85, 0.95 }

local function addCrack(barrier: Barrier, world, seed: number)
	local part = barrier.Part
	local random = Random.new(seed)

	local length = random:NextNumber(part.Size.Y * 0.3, part.Size.Y * 0.7)
	local angle = random:NextNumber(0, math.pi * 2)
	local offsetX = random:NextNumber(-part.Size.X * 0.3, part.Size.X * 0.3)
	local offsetY = random:NextNumber(-part.Size.Y * 0.25, part.Size.Y * 0.25)

	local crack = Build.part({
		Name = "Crack",
		Size = Vector3.new(random:NextNumber(0.25, 0.5), length, part.Size.Z + 0.2),
		CFrame = part.CFrame * CFrame.new(offsetX, offsetY, 0) * CFrame.Angles(0, 0, angle),
		Color = Config.Theme.Ink,
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.15,
		CanCollide = false,
		CastShadow = false,
		Parent = part,
	})

	table.insert(barrier.CrackParts, crack)
end

local function clearCracks(barrier: Barrier)
	for _, crack in barrier.CrackParts do
		crack:Destroy()
	end
	table.clear(barrier.CrackParts)
	barrier.Cracks = 0
end

local function updateCracks(barrier: Barrier, world, ratio: number)
	local wanted = 0
	for _, threshold in CRACK_STEPS do
		if ratio >= threshold then
			wanted += 1
		end
	end

	if wanted == barrier.Cracks then
		return
	end

	if wanted < barrier.Cracks then
		clearCracks(barrier)
	end

	while barrier.Cracks < wanted do
		barrier.Cracks += 1
		addCrack(barrier, world, barrier.Index * 977 + barrier.Cracks * 31)
	end
end

-- Průhlednost dílu Beamy nevypne, musí se zhasnout zvlášť
local function setFieldEnabled(part: BasePart, enabled: boolean)
	for _, child in part:GetChildren() do
		if child:IsA("Beam") then
			child.Enabled = enabled
		end
	end
end

function TrackView:clear()
	if self.Folder then
		self.Folder:Destroy()
		self.Folder = nil
	end
	Textures.reset()
	self.Pickups = {}
	self.Barriers = {}
end

-- Stav ---------------------------------------------------------------------------

--[[
	Bariéry před hráčem musí zmizet (už jsou proražené), ta aktuální drží
	a ukazuje, kolik Poweru chybí. Další v pořadí jsou zamčené a šedivé.
]]
function TrackView:syncBarriers()
	for index, barrier in self.Barriers do
		if index < self.Barrier then
			barrier.Part.CanCollide = false
			barrier.Part.Transparency = 1
			barrier.Label.Text = ""
			setFieldEnabled(barrier.Part, false)
			continue
		end

		barrier.Part.CanCollide = true
		setFieldEnabled(barrier.Part, true)

		if index == self.Barrier then
			local enough = self.Power >= barrier.Required
			barrier.Part.Transparency = 0.25
			barrier.Part.Color = if enough then Config.Theme.Success else self.World.Color
			barrier.Label.Text = if enough
				then `<b>SMASH IT!</b>`
				else `<b>{Format.short(self.Power)} / {Format.short(barrier.Required)}</b>`
			barrier.Label.TextColor3 = if enough then Config.Theme.Success else Config.Theme.Text
		else
			barrier.Part.Transparency = 0.55
			barrier.Part.Color = Config.Theme.PanelLight
			barrier.Label.Text = `<b>{Format.short(barrier.Required)}</b>`
			barrier.Label.TextColor3 = Config.Theme.TextDim
		end
	end
end

function TrackView:setProfile(profile)
	local changedWorld = profile.WorldIndex ~= self.WorldIndex

	self.Power = profile.Power
	self.Barrier = profile.Barrier
	self.PickupValue = profile.PickupValue or 1
	self.CollectRadius = profile.CollectRadius or TRACK.CollectRadius

	if changedWorld then
		self:build(profile.WorldIndex)
	else
		self:syncBarriers()
	end
end

function TrackView:setPower(power: number)
	self.Power = power
	local barrier = self.Barriers[self.Barrier]
	if not barrier then
		CharacterFX.setCharge(0)
		return
	end

	local ratio = power / math.max(barrier.Required, 1)
	CharacterFX.setCharge(ratio)
	updateCracks(barrier, self.World, ratio)

	local enough = power >= barrier.Required
	if enough and not self.WasReady then
		SoundKit.playNamed("Ready", { Position = barrier.Part.Position })
	end
	self.WasReady = enough
	barrier.Part.Color = if enough then Config.Theme.Success else self.World.Color
	barrier.Label.Text = if enough
		then `<b>SMASH IT!</b>`
		else `<b>{Format.short(power)} / {Format.short(barrier.Required)}</b>`
	barrier.Label.TextColor3 = if enough then Config.Theme.Success else Config.Theme.Text
end

-- Proražení bariéry (potvrzené serverem)
function TrackView:breakBarrier(index: number, payload)
	local barrier = self.Barriers[index]
	if not barrier then
		return
	end

	-- Místo nárazu a rychlost hráče rozhodnou, kam a jak daleko kusy odletí
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?

	Effects.smash({
		CFrame = barrier.Part.CFrame,
		Size = barrier.Part.Size,
		World = self.World,
		Payload = payload,
		IsLocal = true,
		Impact = if root then root.Position + Vector3.new(0, 1, 0) else barrier.Part.Position,
		Momentum = if root then root.AssemblyLinearVelocity else Vector3.zero,
	})
	CharacterFX.smash()
	CharacterFX.groundBurst(self.World.Accent)

	barrier.Part.CanCollide = false
	barrier.Part.Transparency = 1
	barrier.Label.Text = ""
	setFieldEnabled(barrier.Part, false)
	clearCracks(barrier)
end

-- Sbírání ------------------------------------------------------------------------

local function hidePickup(pickup: Pickup)
	pickup.Part.Transparency = 1
	pickup.Part.Size = Vector3.new(0.4, 0.4, 0.4)
	pickup.Flying = nil
	pickup.FlyFrom = nil
	local billboard = pickup.Part:FindFirstChild("Info") :: BillboardGui?
	if billboard then
		billboard.Enabled = false
	end
end

--[[
	Start letu k hráči.

	Pickup, který na dotek prostě zmizí, se nedá "cítit". Když místo toho
	vystřelí k hráči a teprve u něj praskne, mozek to přečte jako sebrání.
	Je to nejlevnější úprava s největším dopadem na pocit ze hry.
]]
local function launchPickup(pickup: Pickup, now: number)
	pickup.Flying = now
	pickup.FlyFrom = pickup.Position

	local billboard = pickup.Part:FindFirstChild("Info") :: BillboardGui?
	if billboard then
		billboard.Enabled = false
	end
end

local FLIGHT_SECONDS = 0.22

local function showPickup(pickup: Pickup)
	pickup.Part.Transparency = 0
	TweenService:Create(pickup.Part, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = Vector3.new(2.4, 2.4, 2.4),
	}):Play()
	local billboard = pickup.Part:FindFirstChild("Info") :: BillboardGui?
	if billboard then
		billboard.Enabled = true
	end
end

function TrackView:flush()
	if #self.PendingCollects == 0 then
		return
	end

	Remotes.Collect:FireServer(self.PendingCollects)
	self.PendingCollects = {}
end

-- Seznamy indexů po segmentech se spočítají jednou; v Heartbeatu už se
-- jen čtou, aby se každý snímek nealokovaly nové tabulky.
local SEGMENT_INDICES: { { number } } = {}
for segment = 1, TRACK.BarrierCount do
	SEGMENT_INDICES[segment] = Track.segmentPickups(segment)
end

--[[
	Jediná smyčka hry: respawn, animace i sbírání proběhnou v jednom
	průchodu okolím hráče. Celý svět má přes sto pickupů, ale dál než
	o segment dopředu se hráč stejně nedostane — bariéra ho nepustí.
]]
function TrackView:update(now: number, elapsed: number, root: BasePart)
	local origin = Track.origin(self.WorldIndex)
	local segment = math.clamp(
		math.floor((root.Position.Z - origin.Z) / TRACK.SegmentLength) + 1,
		1,
		TRACK.BarrierCount
	)

	local radius = self.CollectRadius
	local position = root.Position
	local collected = 0

	for offset = -1, 1 do
		local target = segment + offset
		local indices = SEGMENT_INDICES[target]
		if not indices then
			continue
		end

		-- Za aktuální bariéru se hráč nedostane, tamní pickupy neřešíme
		local reachable = target <= self.Barrier

		for _, index in indices do
			local pickup = self.Pickups[index]
			if not pickup then
				continue
			end

			if pickup.ReadyAt > 0 then
				if now < pickup.ReadyAt then
					continue
				end
				pickup.ReadyAt = 0
				showPickup(pickup)
			end

			-- Let se řeší dřív než houpání: letícímu pickupu by se pozice
			-- stejně hned přepsala a je to nejteplejší smyčka ve hře.
			if pickup.Flying then
				local progress = (now - pickup.Flying) / FLIGHT_SECONDS

				if progress >= 1 then
					pickup.ReadyAt = now + TRACK.PickupRespawn
					Effects.pickup(position + Vector3.new(0, 2, 0), self.PickupValue, false)
					hidePickup(pickup)
				else
					-- Zrychluje, ne konstantní rychlost: začátek pomalu,
					-- konec prudce, což vypadá jako přitažení magnetem
					local eased = progress * progress
					local target = position + Vector3.new(0, 1.5, 0)
					local from = pickup.FlyFrom :: Vector3

					pickup.Part.CFrame = CFrame.new(from:Lerp(target, eased))
						* CFrame.Angles(0, elapsed * 14, 0)
					pickup.Part.Size = Vector3.new(2.4, 2.4, 2.4) * (1 - eased * 0.7)
				end
				continue
			end

			local bob = math.sin(elapsed * 2.2 + index) * 0.5
			pickup.Part.CFrame = CFrame.new(pickup.Position + Vector3.new(0, bob, 0))
				* CFrame.Angles(0, elapsed * 1.6 + index, math.rad(20))

			if reachable and (pickup.Position - position).Magnitude <= radius then
				launchPickup(pickup, now)
				table.insert(self.PendingCollects, index)
				collected += 1
			end
		end
	end

	-- Dávkování: server dostane jednu zprávu za desetinu sekundy, ne jednu
	-- za každý sebraný kus.
	if collected > 0 and now - self.LastSendAt >= 0.1 then
		self.LastSendAt = now
		self:flush()
	end

	self:checkBarrier(now, root)
end

function TrackView:checkBarrier(now: number, root: BasePart)
	local barrier = self.Barriers[self.Barrier]
	if not barrier then
		return
	end

	local distance = (barrier.Part.Position - root.Position).Magnitude
	if distance > TRACK.SmashRadius + 6 then
		return
	end

	if self.Power >= barrier.Required then
		if now - self.LastSmashAt < 0.4 then
			return
		end
		self.LastSmashAt = now
		-- Odeslat nasbírané dřív, ať server počítá s aktuálním Powerem
		self:flush()
		Remotes.Smash:FireServer(barrier.Index)
	elseif now - self.LastBlockedAt >= 1.6 then
		self.LastBlockedAt = now
		Effects.blocked(barrier.Part.Position, barrier.Required - self.Power, self.World)
	end
end

function TrackView:start()
	local elapsed = 0

	RunService.Heartbeat:Connect(function(deltaTime)
		elapsed += deltaTime

		if self.WorldIndex == 0 then
			return
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return
		end

		self:update(os.clock(), elapsed, root)
	end)
end

return TrackView

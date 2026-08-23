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

local Effects = require(script.Parent.Effects)

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
}

type Barrier = {
	Index: number,
	Part: BasePart,
	Label: TextLabel,
	Required: number,
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

local function makeBarrier(world, worldIndex: number, index: number, parent: Instance): (BasePart, TextLabel)
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

	for index = 1, TRACK.BarrierCount do
		local part, label = makeBarrier(self.World, worldIndex, index, folder)
		self.Barriers[index] = {
			Index = index,
			Part = part,
			Label = label,
			Required = Config.barrierPower(worldIndex, index),
		}
	end

	self:syncBarriers()
end

function TrackView:clear()
	if self.Folder then
		self.Folder:Destroy()
		self.Folder = nil
	end
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
			continue
		end

		barrier.Part.CanCollide = true

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
		return
	end

	local enough = power >= barrier.Required
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

	Effects.smash(barrier.Part.Position, barrier.Part.Size, self.World, payload, true)

	barrier.Part.CanCollide = false
	barrier.Part.Transparency = 1
	barrier.Label.Text = ""
end

-- Sbírání ------------------------------------------------------------------------

local function hidePickup(pickup: Pickup)
	pickup.Part.Transparency = 1
	pickup.Part.Size = Vector3.new(0.4, 0.4, 0.4)
	local billboard = pickup.Part:FindFirstChild("Info") :: BillboardGui?
	if billboard then
		billboard.Enabled = false
	end
end

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

			local bob = math.sin(elapsed * 2.2 + index) * 0.5
			pickup.Part.CFrame = CFrame.new(pickup.Position + Vector3.new(0, bob, 0))
				* CFrame.Angles(0, elapsed * 1.6 + index, math.rad(20))

			if reachable and (pickup.Position - position).Magnitude <= radius then
				pickup.ReadyAt = now + TRACK.PickupRespawn
				hidePickup(pickup)
				table.insert(self.PendingCollects, index)
				Effects.pickup(pickup.Position, self.PickupValue, false)
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

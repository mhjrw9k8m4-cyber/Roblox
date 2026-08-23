--!strict
--[[
	StationService — přiděluje hráčům stanice a stará se o materiál,
	který se nad pultem vznáší.

	Stav jedné stanice žije jen tady; ASMRService si přes něj sahá
	funkcemi níž, aby logika ran nemusela znát geometrii.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Build = require(Shared.Build)
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)

export type Station = {
	Index: number,
	Folder: Folder,
	Anchor: BasePart,
	Sign: TextLabel,
	Owner: Player?,
	ObjectPart: BasePart?,
	ObjectId: string?,
	Integrity: number,
	MaxIntegrity: number,
	BaseSize: Vector3,
	Combo: number,
	ComboExpiresAt: number,
	LastStrikeAt: number,
}

local StationService = {}

local stations: { Station } = {}
local byPlayer: { [Player]: Station } = {}

function StationService.build()
	local world = WorldService.build()
	local folder = world:WaitForChild("Stanice")

	for index = 1, Config.Core.StationCount do
		local stationFolder = folder:FindFirstChild(`Stanice{index}`) :: Folder
		local sign = stationFolder:FindFirstChild("Cedule") :: BasePart

		stations[index] = {
			Index = index,
			Folder = stationFolder,
			Anchor = stationFolder:FindFirstChild("Kotva") :: BasePart,
			Sign = sign:FindFirstChild("Info"):FindFirstChildOfClass("TextLabel") :: TextLabel,
			Owner = nil,
			ObjectPart = nil,
			ObjectId = nil,
			Integrity = 0,
			MaxIntegrity = 0,
			BaseSize = Vector3.one,
			Combo = 0,
			ComboExpiresAt = 0,
			LastStrikeAt = 0,
		}
	end
end

function StationService.get(player: Player): Station?
	return byPlayer[player]
end

function StationService.all(): { Station }
	return stations
end

local function setSign(station: Station, text: string, color: Color3)
	station.Sign.Text = text
	station.Sign.TextColor3 = color
end

-- Materiál na stanici -----------------------------------------------------

local function clearObject(station: Station)
	if station.ObjectPart then
		station.ObjectPart:Destroy()
		station.ObjectPart = nil
	end
	station.ObjectId = nil
	station.Integrity = 0
	station.MaxIntegrity = 0
end

--[[
	Vytvoří nový kus materiálu nad pultem.
	Velikost roste s tvrdostí materiálu, aby bylo na první pohled vidět,
	že Hvězdný prach je jiná liga než Mýdlo.
]]
function StationService.spawnObject(station: Station)
	local player = station.Owner
	if not player then
		return
	end

	clearObject(station)

	local profile = DataService.get(player)
	if not profile then
		return
	end

	local definition = Config.object(profile.EquippedObject) or Config.Objects[1]
	local tier = Config.objectTier(definition.Id)
	local scale = 5 + math.min(tier - 1, 8) * 0.45

	local part = Build.part({
		Name = "Materiál",
		Shape = Build.shapeOf(definition.Shape),
		Size = Vector3.new(scale, scale, scale),
		CFrame = station.Anchor.CFrame,
		Color = definition.Color,
		Material = definition.Material,
		Anchored = true,
		CanCollide = false,
		CanQuery = true,
		Parent = station.Folder,
	})
	part:SetAttribute("StationIndex", station.Index)
	part:SetAttribute("ObjectId", definition.Id)

	if definition.Material == Enum.Material.Neon or definition.Material == Enum.Material.Glass then
		Build.pointLight(part, definition.Color, 3, 24)
	end

	station.ObjectPart = part
	station.ObjectId = definition.Id
	station.MaxIntegrity = definition.Integrity
	station.Integrity = definition.Integrity
	station.BaseSize = part.Size

	Remotes.ObjectSpawned:FireClient(player, {
		Position = part.Position,
		ObjectId = definition.Id,
		Integrity = station.Integrity,
		MaxIntegrity = station.MaxIntegrity,
	})
end

-- Vizuálně zmenší materiál podle zbývající integrity
function StationService.refreshObjectVisual(station: Station)
	local part = station.ObjectPart
	if not part or station.MaxIntegrity <= 0 then
		return
	end

	local ratio = math.clamp(station.Integrity / station.MaxIntegrity, 0, 1)
	-- nikdy nezmizí úplně, aby zůstal cíl, do kterého se dá seknout
	local scale = 0.35 + 0.65 * ratio
	part.Size = station.BaseSize * scale
end

-- Přidělení stanic --------------------------------------------------------

local function freeStation(): Station?
	for _, station in stations do
		if not station.Owner then
			return station
		end
	end
	return nil
end

function StationService.assign(player: Player): Station?
	if byPlayer[player] then
		return byPlayer[player]
	end

	local station = freeStation()
	if not station then
		Remotes.Notify:FireClient(player, {
			Text = "Všechny stanice jsou plné, zkus jiný server.",
			Kind = "warn",
		})
		return nil
	end

	station.Owner = player
	station.Combo = 0
	station.ComboExpiresAt = 0
	byPlayer[player] = station

	setSign(station, `<b>{player.DisplayName}</b>`, Config.Theme.Accent)
	StationService.spawnObject(station)

	return station
end

function StationService.release(player: Player)
	local station = byPlayer[player]
	if not station then
		return
	end

	clearObject(station)
	station.Owner = nil
	station.Combo = 0
	byPlayer[player] = nil
	setSign(station, "<b>VOLNÁ STANICE</b>", Config.Theme.TextDim)
end

-- Postaví hráče k jeho stanici (po spawnu i po přepnutí materiálu)
function StationService.teleport(player: Player)
	local station = byPlayer[player]
	local character = player.Character
	if not station or not character then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local base = WorldService.stationCFrame(station.Index)
	-- kousek před pultem, čelem ke stanici
	root.CFrame = base * CFrame.new(0, 4, 8) * CFrame.Angles(0, math.pi, 0)
end

-- Vznášení a rotace materiálu --------------------------------------------

function StationService.start()
	local elapsed = 0

	RunService.Heartbeat:Connect(function(deltaTime)
		elapsed += deltaTime

		for _, station in stations do
			local part = station.ObjectPart
			if part then
				local bob = math.sin(elapsed * 1.6 + station.Index) * 0.6
				local spin = elapsed * 0.8 + station.Index
				part.CFrame = station.Anchor.CFrame * CFrame.new(0, bob, 0) * CFrame.Angles(0, spin, 0)
			end
		end
	end)

	Players.PlayerRemoving:Connect(StationService.release)
end

return StationService

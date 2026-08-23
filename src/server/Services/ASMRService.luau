--!strict
--[[
	ASMRService — srdce hry: jedna rána do materiálu.

	Server je autorita. Klient jen řekne "sekl jsem"; tady se ověří
	vzdálenost i prodleva, spočítá combo, poškození, peníze a XP,
	a teprve pak se efekt rozešle všem klientům.

	Full profil se po každé ráně neposílá — to by byl zbytečný provoz.
	Klient dostane v efektu nový stav peněz a plný profil přijde
	při nákupu, level upu a v pravidelné synchronizaci.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local StationService = require(script.Parent.StationService)

local ASMRService = {}

-- Tolerance prodlevy: síť kolísá, hráč nemá být trestán za lag.
local COOLDOWN_TOLERANCE = 0.9
-- Tvrdý strop, aby ani vadný klient neposlal tisíc ran za vteřinu.
local ABSOLUTE_MAX_RATE = 30

local autoLoops: { [Player]: thread } = {}
local rateWindow: { [Player]: { Count: number, Since: number } } = {}

local function withinRateLimit(player: Player): boolean
	local now = os.clock()
	local window = rateWindow[player]

	if not window or now - window.Since >= 1 then
		rateWindow[player] = { Count = 1, Since = now }
		return true
	end

	window.Count += 1
	return window.Count <= ABSOLUTE_MAX_RATE
end

local function inRange(player: Player, station: StationService.Station): boolean
	local character = player.Character
	if not character then
		return false
	end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end

	return (root.Position - station.Anchor.Position).Magnitude <= Config.Core.MaxStrikeDistance
end

local function comboMultiplier(station: StationService.Station, profile: any): number
	local now = os.clock()

	if now <= station.ComboExpiresAt then
		station.Combo += 1
	else
		station.Combo = 1
	end

	station.ComboExpiresAt = now + Config.Core.ComboWindow

	local raw = 1 + (station.Combo - 1) * Config.Core.ComboStep
	return math.min(raw, Economy.comboMax(profile))
end

--[[
	Provede jednu ránu. `isAuto` odlišuje auto-řez, který ignoruje
	vstup hráče, ale jinak počítá stejně (jen bez komba, aby se
	nedalo comba držet nekonečně bez hraní).
]]
function ASMRService.strike(player: Player, isAuto: boolean?): boolean
	local profile = DataService.get(player)
	local station = StationService.get(player)
	if not profile or not station or not station.ObjectPart or not station.ObjectId then
		return false
	end

	local now = os.clock()

	if not isAuto then
		if not withinRateLimit(player) then
			return false
		end
		if now - station.LastStrikeAt < Economy.cooldown(profile) * COOLDOWN_TOLERANCE then
			return false
		end
		if not inRange(player, station) then
			return false
		end
		station.LastStrikeAt = now
	end

	local definition = Config.object(station.ObjectId)
	if not definition then
		return false
	end

	local multiplier = if isAuto then 1 else comboMultiplier(station, profile)
	local damage = Economy.damage(profile)
	local dealt = math.min(damage, station.Integrity)

	station.Integrity -= dealt
	StationService.refreshObjectVisual(station)

	local coins = Economy.strikeReward(profile, station.ObjectId, dealt, multiplier)
	local xpGain = definition.Xp * (dealt / definition.Integrity)

	profile.Coins += coins
	profile.TotalStrikes += 1
	local levelsGained = Economy.addXp(profile, xpGain)
	DataService.markDirty(player)

	local destroyed = station.Integrity <= 0

	-- Efekt vidí a slyší i ostatní hráči — ASMR se poslouchá líp ve dvou.
	Remotes.StrikeEffect:FireAllClients({
		UserId = player.UserId,
		Position = station.ObjectPart.Position,
		ObjectId = station.ObjectId,
		ToolId = profile.EquippedTool,
		Coins = coins,
		Combo = station.Combo,
		Multiplier = multiplier,
		Ratio = math.clamp(station.Integrity / math.max(station.MaxIntegrity, 1), 0, 1),
		Auto = isAuto == true,
	})

	if levelsGained > 0 then
		Remotes.LevelUp:FireClient(player, profile.Level)
		ASMRService.pushProfile(player)
	end

	if destroyed then
		ASMRService.finishObject(player, station, profile)
	end

	return true
end

function ASMRService.finishObject(player: Player, station: StationService.Station, profile: any)
	local objectId = station.ObjectId
	if not objectId then
		return
	end

	local definition = Config.object(objectId)
	local bonus = Economy.destroyBonus(profile, objectId)

	profile.Coins += bonus
	profile.TotalDestroyed += 1
	local levelsGained = Economy.addXp(profile, (definition and definition.Xp or 0) * 0.5)
	DataService.markDirty(player)

	Remotes.ObjectDestroyed:FireAllClients({
		UserId = player.UserId,
		Position = station.ObjectPart and station.ObjectPart.Position or station.Anchor.Position,
		ObjectId = objectId,
		Bonus = bonus,
		Combo = station.Combo,
	})

	if levelsGained > 0 then
		Remotes.LevelUp:FireClient(player, profile.Level)
	end

	ASMRService.pushProfile(player)

	-- Krátká pauza, ať doběhne efekt rozpadu, pak nový kus
	task.delay(0.45, function()
		if StationService.get(player) == station and station.Owner == player then
			StationService.spawnObject(station)
		end
	end)
end

-- Pošle klientovi kompletní profil (po nákupu, level upu, synchronizaci)
function ASMRService.pushProfile(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end

	Remotes.ProfileChanged:FireClient(player, ASMRService.serialize(player, profile))
end

-- Profil očištěný o runtime pole + spočítané hodnoty pro UI
function ASMRService.serialize(player: Player, profile: any)
	local station = StationService.get(player)

	return {
		Coins = profile.Coins,
		Xp = profile.Xp,
		Level = profile.Level,
		Tools = profile.Tools,
		EquippedTool = profile.EquippedTool,
		Objects = profile.Objects,
		EquippedObject = profile.EquippedObject,
		Upgrades = profile.Upgrades,
		Rebirths = profile.Rebirths,
		Playtime = DataService.playtime(player),
		ClaimedRewards = profile.ClaimedRewards,
		TotalStrikes = profile.TotalStrikes,
		TotalDestroyed = profile.TotalDestroyed,
		Stats = Economy.stats(profile),
		CoinsPerSecond = Economy.coinsPerSecond(profile),
		Integrity = station and station.Integrity or 0,
		MaxIntegrity = station and station.MaxIntegrity or 0,
		CanSave = profile._canSave ~= false,
	}
end

-- Auto-řez ----------------------------------------------------------------

function ASMRService.refreshAutoLoop(player: Player)
	local existing = autoLoops[player]
	if existing then
		task.cancel(existing)
		autoLoops[player] = nil
	end

	local profile = DataService.get(player)
	if not profile then
		return
	end

	local rate = Economy.autoRate(profile)
	if rate <= 0 then
		return
	end

	autoLoops[player] = task.spawn(function()
		local interval = 1 / rate
		while player.Parent do
			task.wait(interval)
			ASMRService.strike(player, true)
		end
	end)
end

function ASMRService.stopAutoLoop(player: Player)
	local existing = autoLoops[player]
	if existing then
		task.cancel(existing)
		autoLoops[player] = nil
	end
	rateWindow[player] = nil
end

function ASMRService.start()
	Remotes.Strike.OnServerEvent:Connect(function(player)
		ASMRService.strike(player, false)
	end)

	Players.PlayerRemoving:Connect(ASMRService.stopAutoLoop)

	-- Pravidelná synchronizace: srovná klientův odhad se serverem
	-- a udržuje aktuální odehraný čas pro odměny.
	task.spawn(function()
		while true do
			task.wait(5)
			for _, player in Players:GetPlayers() do
				if DataService.get(player) then
					ASMRService.pushProfile(player)
				end
			end
		end
	end)
end

return ASMRService

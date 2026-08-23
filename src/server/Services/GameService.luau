--!strict
--[[
	GameService — jádro hry: sbírání "+1" a prorážení bariér.

	Rozdělení odpovědnosti:
	  Klient staví pickupy a tabule lokálně (musí mizet a blokovat každému
	  zvlášť) a hlásí, co sebral a co chce prorazit.
	  Server nic z toho nebere na slovo — u každého pickupu ověří, že hráč
	  je opravdu u něj, že ho nesebral před chvílí a že vůbec smí být tak
	  daleko v trati. Power tedy roste jen tak, jak dovolí server.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Track = require(Shared.Track)

local DataService = require(script.Parent.DataService)

local GameService = {}

local TRACK = Config.Track

-- Kolik pickupů a průrazů za sekundu server vůbec připustí. Poctivý hráč
-- se k těmhle číslům nedostane ani s plným magnetem.
local MAX_COLLECTS_PER_SECOND = 45
local MAX_SMASHES_PER_SECOND = 6
-- Tolerance na dosah: klient sbírá podle své pozice o snímek dřív.
local RANGE_TOLERANCE = 6

type Window = { Count: number, Since: number }

local pickupCooldowns: { [Player]: { [number]: number } } = {}
local collectWindow: { [Player]: Window } = {}
local smashWindow: { [Player]: Window } = {}
local lastAutoAt: { [Player]: number } = {}

local function withinRate(windows: { [Player]: Window }, player: Player, limit: number): boolean
	local now = os.clock()
	local window = windows[player]

	if not window or now - window.Since >= 1 then
		windows[player] = { Count = 1, Since = now }
		return true
	end

	window.Count += 1
	return window.Count <= limit
end

local function rootPosition(player: Player): Vector3?
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root and root.Position
end

-- Power ---------------------------------------------------------------------

local function pushPower(player: Player, profile: any, gained: number, source: string)
	Remotes.PowerChanged:FireClient(player, {
		Power = profile.Power,
		Gained = gained,
		Source = source,
	})
end

function GameService.addPower(player: Player, profile: any, amount: number, source: string)
	if amount <= 0 then
		return
	end

	profile.Power += amount
	DataService.markDirty(player)
	pushPower(player, profile, amount, source)
end

-- Sbírání -------------------------------------------------------------------

--[[
	Klient posílá dávku indexů najednou (magnet jich sebere víc v jednom
	snímku). Vracet se nic nemusí — výsledek přijde v PowerChanged.
]]
function GameService.onCollect(player: Player, indices: { number })
	local profile = DataService.get(player)
	if not profile or typeof(indices) ~= "table" then
		return
	end

	local position = rootPosition(player)
	if not position then
		return
	end

	local now = os.clock()
	local cooldowns = pickupCooldowns[player]
	if not cooldowns then
		cooldowns = {}
		pickupCooldowns[player] = cooldowns
	end

	local radius = Economy.collectRadius(profile) + RANGE_TOLERANCE
	local pickupValue = Economy.pickupValue(profile, os.time())
	local luck = Economy.luckChance(profile)
	local gained = 0
	local crits = 0

	for _, index in indices do
		if typeof(index) ~= "number" or index ~= index then
			continue
		end
		if not withinRate(collectWindow, player, MAX_COLLECTS_PER_SECOND) then
			break
		end

		index = math.floor(index)

		-- Za svou aktuální bariéru se hráč fyzicky nedostane, takže ani
		-- tamní pickupy nemůže sbírat.
		if Track.pickupSegment(index) > profile.Barrier then
			continue
		end

		local target = Track.pickupPosition(profile.WorldIndex, index)
		if not target then
			continue
		end
		if (target - position).Magnitude > radius then
			continue
		end

		local readyAt = cooldowns[index]
		if readyAt and now < readyAt then
			continue
		end
		cooldowns[index] = now + TRACK.PickupRespawn

		local value = pickupValue
		if luck > 0 and math.random() < luck then
			value *= 5
			crits += 1
		end
		gained += value
	end

	if gained > 0 then
		profile.Power += gained
		DataService.markDirty(player)
		Remotes.PowerChanged:FireClient(player, {
			Power = profile.Power,
			Gained = gained,
			Source = "collect",
			Crits = crits,
		})
	end
end

-- Prorážení -----------------------------------------------------------------

local function worldCleared(player: Player, profile: any)
	local worldIndex = profile.WorldIndex
	local world = Config.Worlds[worldIndex]

	-- Bonus za dokončení kola: dvojnásobek součtu všech bariér ve světě
	local total = 0
	for index = 1, TRACK.BarrierCount do
		total += Config.barrierCoins(worldIndex, index)
	end

	local bonus = math.floor(total * 2 * Economy.coinMultiplier(profile, os.time()))
	local gems = world.Gems

	profile.Coins += bonus
	profile.Gems += gems
	profile.Barrier = 1
	profile.Power = 0
	DataService.markDirty(player)

	-- Bariéry se zase zavřou, takže hráče musíme vrátit na start —
	-- jinak by zůstal uvězněný za poslední z nich.
	GameService.teleport(player)

	Remotes.Notify:FireClient(player, {
		Text = `{world.Name} cleared! +{Format.short(bonus)} 💰  +{gems} 💎`,
		Kind = "success",
		Sound = "WorldClear",
	})
end

function GameService.onSmash(player: Player, barrierIndex: number)
	local profile = DataService.get(player)
	if not profile or typeof(barrierIndex) ~= "number" then
		return
	end
	if not withinRate(smashWindow, player, MAX_SMASHES_PER_SECOND) then
		return
	end

	barrierIndex = math.floor(barrierIndex)

	-- Bariéry se prorážejí po pořadě; jiné číslo než aktuální je nesmysl.
	if barrierIndex ~= profile.Barrier or barrierIndex > TRACK.BarrierCount then
		return
	end

	local required = Config.barrierPower(profile.WorldIndex, barrierIndex)
	if profile.Power < required then
		return
	end

	local position = rootPosition(player)
	local target = Track.barrierPosition(profile.WorldIndex, barrierIndex)
	if not position or (target - position).Magnitude > TRACK.SmashRadius + RANGE_TOLERANCE + 8 then
		return
	end

	local coins = Economy.smashReward(profile, barrierIndex, os.time())

	profile.Coins += coins
	profile.Smashes += 1
	profile.Barrier += 1
	DataService.markDirty(player)

	-- Efekt vidí všichni ve světě — rozpad tabule je hlavní podívaná.
	Remotes.SmashEffect:FireAllClients({
		UserId = player.UserId,
		WorldIndex = profile.WorldIndex,
		Barrier = barrierIndex,
		Coins = coins,
	})

	if profile.Barrier > TRACK.BarrierCount then
		worldCleared(player, profile)
	end

	GameService.pushProfile(player)
end

-- Světy ---------------------------------------------------------------------

--[[
	Přechod do jiného světa. Power je postup v rámci jednoho světa,
	takže se vynuluje — jinak by hráč vešel do dalšího světa s hotovými
	bariérami a přeskočil celý jeho obsah.
]]
function GameService.enterWorld(player: Player, worldIndex: number): boolean
	local profile = DataService.get(player)
	if not profile then
		return false
	end

	local world = Config.Worlds[worldIndex]
	if not world or not profile.Worlds[world.Id] then
		return false
	end

	if profile.WorldIndex ~= worldIndex then
		profile.WorldIndex = worldIndex
		profile.Power = 0
		profile.Barrier = 1
		pickupCooldowns[player] = {}
		DataService.markDirty(player)
	end

	GameService.teleport(player)
	Remotes.WorldChanged:FireClient(player, worldIndex)
	GameService.pushProfile(player)

	return true
end

function GameService.teleport(player: Player)
	local profile = DataService.get(player)
	local character = player.Character
	if not profile or not character then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	root.CFrame = Track.spawnCFrame(profile.WorldIndex)
end

function GameService.applyCharacter(player: Player)
	local profile = DataService.get(player)
	local character = player.Character
	if not profile or not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Economy.walkSpeed(profile)
	end
end

-- Profil pro klienta ---------------------------------------------------------

function GameService.serialize(player: Player, profile: any)
	local now = os.time()

	return {
		Coins = profile.Coins,
		Gems = profile.Gems,
		Power = profile.Power,
		WorldIndex = profile.WorldIndex,
		Barrier = profile.Barrier,
		Worlds = profile.Worlds,
		Upgrades = profile.Upgrades,
		Boosts = profile.Boosts,
		Title = profile.Title,
		Rebirths = profile.Rebirths,
		Smashes = profile.Smashes,
		Playtime = DataService.playtime(player),
		NextChestAt = profile.NextChestAt,
		PickupValue = Economy.pickupValue(profile, now),
		CollectRadius = Economy.collectRadius(profile),
		AutoRate = Economy.autoRate(profile, now),
		CoinsPerSecond = Economy.coinsPerSecond(profile, now),
		RebirthMultiplier = Economy.rebirthMultiplier(profile),
		ServerTime = now,
		CanSave = profile._canSave ~= false,
	}
end

function GameService.pushProfile(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	Remotes.ProfileChanged:FireClient(player, GameService.serialize(player, profile))
end

-- Auto Collect ---------------------------------------------------------------

--[[
	Auto sbírání řeší server sám: přičte, co by hráč za tu dobu sebral.
	Kdyby to počítal klient, byl by to jen další kanál, který jde zneužít.
]]
local function tickAuto()
	local now = os.clock()

	for _, player in Players:GetPlayers() do
		local profile = DataService.get(player)
		if not profile then
			continue
		end

		-- Bez tohohle by první tik nikdy nenastavil výchozí čas
		-- a `elapsed` by zůstal na nule napořád.
		local last = lastAutoAt[player]
		if not last then
			lastAutoAt[player] = now
			continue
		end

		local rate = Economy.autoRate(profile, os.time())
		if rate <= 0 then
			lastAutoAt[player] = now
			continue
		end

		local elapsed = now - last
		if elapsed < 1 then
			continue
		end
		lastAutoAt[player] = now

		local gained = math.floor(Economy.pickupValue(profile, os.time()) * rate * elapsed)
		GameService.addPower(player, profile, gained, "auto")
	end
end

function GameService.start()
	Remotes.Collect.OnServerEvent:Connect(function(player, indices)
		GameService.onCollect(player, indices)
	end)

	Remotes.Smash.OnServerEvent:Connect(function(player, barrierIndex)
		GameService.onSmash(player, barrierIndex)
	end)

	Remotes.EnterWorld.OnServerInvoke = function(player, worldIndex)
		if typeof(worldIndex) ~= "number" then
			return { Ok = false, Message = "Invalid world." }
		end
		local ok = GameService.enterWorld(player, math.floor(worldIndex))
		return { Ok = ok, Message = if ok then nil else "World is locked." }
	end

	Remotes.GetProfile.OnServerInvoke = function(player)
		local profile = DataService.await(player, 20)
		if not profile then
			return nil
		end
		return GameService.serialize(player, profile)
	end

	Players.PlayerRemoving:Connect(function(player)
		pickupCooldowns[player] = nil
		collectWindow[player] = nil
		smashWindow[player] = nil
		lastAutoAt[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			tickAuto()
		end
	end)

	-- Pravidelná synchronizace: srovná klientův odhad se serverem
	task.spawn(function()
		while true do
			task.wait(5)
			for _, player in Players:GetPlayers() do
				if DataService.get(player) then
					GameService.pushProfile(player)
				end
			end
		end
	end)
end

return GameService

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
local Combo = require(Shared.Combo)
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Perks = require(Shared.Perks)
local Remotes = require(Shared.Remotes)
local Track = require(Shared.Track)

local DataService = require(script.Parent.DataService)
local Guard = require(script.Parent.GuardService)

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
local combos: { [Player]: Combo.State } = {}
-- Nejvyšší řetěz od posledního dojetého kola; posílá se do analytiky.
-- Průměr by nic neřekl (většinu času je řetěz nízký), maximum ano.
local comboPeak: { [Player]: number } = {}
-- Kdy hráči vyprší nálet. V paměti, ne v profilu: trvá pár vteřin,
-- takže by se do DataStore stejně nestihl propsat.
local surgeUntil: { [Player]: number } = {}

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

local function comboFor(player: Player): Combo.State
	local existing = combos[player]
	if existing then
		return existing
	end

	local fresh = Combo.new()
	combos[player] = fresh
	return fresh
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

	local radius = Economy.collectRadius(profile, surgeUntil[player], os.time()) + RANGE_TOLERANCE
	local pickupValue = Economy.pickupValue(profile, os.time())
	local luck = Economy.luckChance(profile)
	local combo = comboFor(player)
	local window = Economy.comboWindow(profile)
	local lap = Economy.lap(profile)
	local gained = 0
	local crits = 0
	local goldens = 0
	local accepted = 0

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

		--[[
			Násobič se počítá po každém článku zvlášť, ne až na konec dávky.
			Jinak by magnet, který sebere deset pickupů v jednom snímku,
			dostal za všech deset násobič, jaký měl hráč před nimi —
			a naopak by ho nedostal ten, kdo sbírá poctivě jeden po druhém.
		]]
		local chain = Combo.step(combo, 1, now, window)
		if chain > (comboPeak[player] or 0) then
			comboPeak[player] = chain
		end

		local value = pickupValue * Combo.multiplier(chain)

		-- Zlatý pickup se pozná ze stejného vzorce jako na klientovi,
		-- takže se nemusí posílat, které to jsou — a nedá se vybrat.
		local golden = Track.isGolden(profile.WorldIndex, lap, index)
		if golden then
			value *= TRACK.GoldenValue
			goldens += 1
		end

		if luck > 0 and math.random() < luck then
			value *= 5
			crits += 1
		end
		gained += math.floor(value)
		accepted += 1
	end

	if gained > 0 then
		profile.Power += gained
		DataService.markDirty(player)
		-- Do úkolu se počítá jen to, co server uznal, ne co klient poslal
		local Retention = require(script.Parent.RetentionService)
		Retention.progress(player, "collect", accepted)
		-- Úkol na combo je maximum dosaženého řetězu, ne součet článků
		Retention.reach(player, "combo", Combo.value(combo, now, window))
		require(script.Parent.AnalyticsService).onboarding(player, "FirstPickup")
		Remotes.PowerChanged:FireClient(player, {
			Power = profile.Power,
			Gained = gained,
			Source = "collect",
			Crits = crits,
			Goldens = goldens,
			Combo = Combo.value(combo, now, window),
			Window = window,
		})
	end
end

-- Prorážení -----------------------------------------------------------------

local function worldCleared(player: Player, profile: any)
	local worldIndex = profile.WorldIndex
	local world = Config.Worlds[worldIndex]
	local lap = Economy.lap(profile, worldIndex)

	-- Bonus za dokončení kola: dvojnásobek součtu všech bariér ve světě
	local total = 0
	for index = 1, TRACK.BarrierCount do
		total += Economy.barrierCoins(profile, index, worldIndex)
	end

	local bonus = math.floor(total * 2 * Economy.coinMultiplier(profile, os.time()))
	local gems = Economy.clearGems(profile, worldIndex)

	profile.Coins += bonus
	profile.Gems += gems
	profile.Barrier = 1
	profile.Power = 0

	-- Další kolo téhož světa: zdi i výplata povyskočí. Bez toho by hráč
	-- po pár upgradech projížděl svět, aniž by musel cokoliv sbírat.
	profile.Laps = profile.Laps or {}
	profile.Laps[world.Id] = lap + 1

	DataService.markDirty(player)
	require(script.Parent.RetentionService).progress(player, "clear", 1)

	require(script.Parent.AnalyticsService).custom(player, "lap", lap + 1, {
		World = world.Id,
		ComboPeak = comboPeak[player] or 0,
	})
	comboPeak[player] = 0

	-- Bariéry se zase zavřou, takže hráče musíme vrátit na start —
	-- jinak by zůstal uvězněný za poslední z nich.
	GameService.teleport(player)

	Remotes.Notify:FireClient(player, {
		Text = `{world.Name} LAP {lap + 1} DONE! +{Format.short(bonus)} 💰  +{gems} 💎  ·  walls got tougher`,
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

	local required = Economy.barrierPower(profile, barrierIndex)
	if profile.Power < required then
		return
	end

	local position = rootPosition(player)
	local target = Track.barrierPosition(profile.WorldIndex, barrierIndex)
	if not position or (target - position).Magnitude > TRACK.SmashRadius + RANGE_TOLERANCE + 8 then
		return
	end

	local coins = Economy.smashReward(profile, barrierIndex, os.time())
	-- Přeplácnutí se posílá klientovi, aby se dalo ukázat. Bez toho je to
	-- systém, který hráče odměňuje, ale on o něm nemá jak vědět.
	local overkill = Economy.overkill(profile.Power, required, profile)

	--[[
		Průraz s rozjetým řetězem zapne nálet: rychlost i dosah se zvednou,
		takže hráč doběhne k dalším pickupům dřív a řetěz udrží.

		Tím vzniká smyčka, která dosud chyběla:
		    drž řetěz → proraž → nálet → řetěz vydrží → proraž…

		Odměnou je tedy udržení řetězu, ne samotný průraz.
	]]
	local surged = Economy.surgeTriggered(Combo.value(combos[player], os.clock(), Economy.comboWindow(profile)))
	if surged then
		surgeUntil[player] = os.time() + TRACK.SurgeSeconds
		GameService.applyCharacter(player)
	end

	profile.Coins += coins
	profile.Smashes += 1
	profile.Barrier += 1
	DataService.markDirty(player)
	require(script.Parent.RetentionService).progress(player, "smash", 1)

	-- Do serverové události přispívá hráč tím, co stejně dělá —
	-- nemusí nikam chodit ani nic přepínat.
	require(script.Parent.EventService).contribute(player, coins)

	local Analytics = require(script.Parent.AnalyticsService)
	Analytics.onboarding(player, "FirstSmash")
	Analytics.economy(player, "Source", "Coins", coins, profile.Coins, "wall_smashed")

	-- Efekt vidí všichni ve světě — rozpad tabule je hlavní podívaná.
	Remotes.SmashEffect:FireAllClients({
		UserId = player.UserId,
		WorldIndex = profile.WorldIndex,
		Barrier = barrierIndex,
		Coins = coins,
		Overkill = overkill,
		Surge = surged,
		-- Kolik zdí do konce kola; klient podle toho stupňuje efekt
		Left = TRACK.BarrierCount - barrierIndex,
	})

	if profile.Barrier > TRACK.BarrierCount then
		worldCleared(player, profile)
		require(script.Parent.AnalyticsService).world(player, profile.WorldIndex, true)
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
		-- Řetěz patří k jedné trati; přenášet ho do jiného světa
		-- by znamenalo vstoupit do něj s hotovým násobičem.
		Combo.reset(comboFor(player))
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
		humanoid.WalkSpeed = Economy.walkSpeed(profile, surgeUntil[player], os.time())
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
		CollectRadius = Economy.collectRadius(profile, surgeUntil[player], now),
		-- Klient ji potřebuje, aby po hitstopu obnovil právě tu rychlost,
		-- kterou server povolil — ne tu, co si zapamatoval sám.
		WalkSpeed = Economy.walkSpeed(profile, surgeUntil[player], now),
		AutoRate = Economy.autoRate(profile, now),
		CoinsPerSecond = Economy.coinsPerSecond(profile, now),
		RebirthMultiplier = Economy.rebirthMultiplier(profile),
		PetMultiplier = Economy.petMultiplier(profile),
		Pets = require(script.Parent.PetService).snapshot(profile),
		EquippedPets = profile.EquippedPets,
		PetSlots = require(script.Parent.PetService).slots(profile),
		Hatched = profile.Hatched,
		Passes = profile.Passes,
		Settings = profile.Settings,
		Cosmetics = profile.Cosmetics,
		Combo = Combo.value(combos[player], os.clock(), Economy.comboWindow(profile)),
		ComboWindow = Economy.comboWindow(profile),
		Laps = profile.Laps,
		Perks = profile.Perks,
		PerkTokens = Perks.available(profile),
		DailyStreak = profile.DailyDay,
		QuestStreak = profile.QuestStreak,
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
	--[[
		Collect a Smash schválně nejdou přes Guard: mají vlastní, mnohem
		přísnější limit počítaný na sekundu (viz `withinRate` nahoře),
		protože chodí desetkrát častěji než cokoliv jiného.
	]]
	Remotes.Collect.OnServerEvent:Connect(function(player, indices)
		GameService.onCollect(player, indices)
	end)

	Remotes.Smash.OnServerEvent:Connect(function(player, barrierIndex)
		GameService.onSmash(player, barrierIndex)
	end)

	Guard.wrapFunction("EnterWorld", "Write", function(player, worldIndex)
		if typeof(worldIndex) ~= "number" or worldIndex ~= worldIndex then
			return { Ok = false, Message = "Invalid world." }
		end
		local ok = GameService.enterWorld(player, math.floor(worldIndex))
		return { Ok = ok, Message = if ok then nil else "World is locked." }
	end)

	Guard.wrapFunction("GetProfile", "Cheap", function(player)
		local profile = DataService.await(player, 20)
		if not profile then
			return nil
		end
		return GameService.serialize(player, profile)
	end)

	--[[
		Nastavení si drží klient a posílá ho k uložení. Neovlivňuje nic,
		co by šlo zneužít (hlasitost, skrytí UI, méně efektů), takže se
		jen ověří tvar a uloží.
	]]
	Guard.wrapEvent("SaveSettings", "Cheap", function(player, settings)
		local profile = DataService.get(player)
		if not profile or typeof(settings) ~= "table" then
			return
		end

		for _, key in { "Music", "Sfx", "HideUi", "LowGraphics" } do
			if typeof(settings[key]) == "boolean" then
				profile.Settings[key] = settings[key]
			end
		end

		DataService.markDirty(player)
	end)

	--[[
		Doběh náletu. Kdyby se rychlost neobnovila, hráč by zrychlení
		držel napořád — jediné místo, kde se jinak přepočítává, je nákup
		Speed upgradu, a na ten čekat nemůžeme.

		Půl sekundy stačí: konec náletu není moment, který by se dal
		propásnout, a častější tik by jen zbytečně sahal na Humanoida.
	]]
	task.spawn(function()
		while true do
			task.wait(0.5)

			local now = os.time()
			for player, expires in surgeUntil do
				if now >= expires then
					surgeUntil[player] = nil
					if player.Parent then
						GameService.applyCharacter(player)
					end
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		pickupCooldowns[player] = nil
		collectWindow[player] = nil
		smashWindow[player] = nil
		lastAutoAt[player] = nil
		combos[player] = nil
		comboPeak[player] = nil
		surgeUntil[player] = nil
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

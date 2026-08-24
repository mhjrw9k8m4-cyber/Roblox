--!strict
--[[
	DataService — načítání a ukládání profilu.

	Odolnost:
	  * načtení i uložení běží přes pcall s exponenciálním backoffem,
	  * když DataStore selže (typicky Studio bez API access), hra běží dál,
	    ale ukládání se pro tu session vypne — jinak by se hráči přepsal
	    skutečný postup výchozími nulami,
	  * BindToClose uloží všechny hráče při vypnutí serveru.

	Uložený čas odchodu slouží k offline výdělkům, proto se ukládá
	`LeftAt` jako os.time() (reálný čas), ne os.clock().
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

export type Profile = {
	Coins: number,
	Gems: number,
	Power: number, -- postup v aktuálním světě, resetuje se při přechodu
	WorldIndex: number,
	Barrier: number, -- první ještě neproražená bariéra (1..BarrierCount+1)
	Worlds: { [string]: boolean },
	Upgrades: { [string]: number },
	Boosts: { [string]: number }, -- id -> unixový čas vypršení
	Title: string,
	Rebirths: number,
	Smashes: number,
	Playtime: number,
	NextChestAt: number, -- unixový čas, kdy je truhla znovu k dispozici
	LeftAt: number,

	-- Retence
	DailyDay: number, -- na kolikátém dni sedmidenního kolotoče hráč je
	DailyClaimedOn: number, -- index dne, kdy si naposled vzal odměnu
	QuestDay: number, -- index dne, pro který jsou vygenerované úkoly
	Quests: { any },
	QuestStreak: number,
	Codes: { [string]: boolean },

	-- Pety
	Pets: { [string]: number }, -- id -> počet kusů
	EquippedPets: { string },
	Hatched: number,

	-- Placené a milníky
	Passes: { [string]: boolean },
	Badges: { [string]: boolean },
	Spent: number, -- kolik peněz hráč celkem utratil (pro úkoly)
	Settings: { [string]: any },

	-- runtime, neukládá se
	_dirty: boolean?,
	_canSave: boolean?,
	_sessionStart: number?,
}

local DataService = {}

local store = DataStoreService:GetDataStore(Config.GameName .. "_v1")
local profiles: { [Player]: Profile } = {}

local function defaultProfile(): Profile
	return {
		Coins = 0,
		Gems = 5,
		Power = 0,
		WorldIndex = 1,
		Barrier = 1,
		Worlds = { [Config.Worlds[1].Id] = true },
		Upgrades = {},
		Boosts = {},
		Title = Config.Titles[1].Id,
		Rebirths = 0,
		Smashes = 0,
		Playtime = 0,
		NextChestAt = 0,
		LeftAt = 0,

		DailyDay = 0,
		DailyClaimedOn = 0,
		QuestDay = 0,
		Quests = {},
		QuestStreak = 0,
		Codes = {},

		Pets = {},
		EquippedPets = {},
		Hatched = 0,

		Passes = {},
		Badges = {},
		Spent = 0,
		Settings = { Music = true, Sfx = true, HideUi = false, LowGraphics = false },
	}
end

-- Doplní chybějící klíče a opraví nesmyslné hodnoty (staré profily
-- po updatu hry, nebo poškozený zápis).
local function reconcile(raw: any): Profile
	local profile = raw
	local template = defaultProfile()

	for key, value in template do
		if profile[key] == nil then
			profile[key] = value
		end
	end

	-- Nasazených petů nesmí být víc, než kolik jich hráč vlastní —
	-- jinak by po smazání petu z configu zůstal viset neplatný odkaz.
	local equipped = {}
	for _, petId in profile.EquippedPets do
		if (profile.Pets[petId] or 0) > 0 then
			table.insert(equipped, petId)
		end
	end
	profile.EquippedPets = equipped

	profile.Worlds[Config.Worlds[1].Id] = true
	profile.WorldIndex = math.clamp(math.floor(profile.WorldIndex), 1, #Config.Worlds)
	profile.Barrier = math.clamp(math.floor(profile.Barrier), 1, Config.Track.BarrierCount + 1)
	profile.Power = math.max(profile.Power, 0)

	-- Nasazený svět musí být odemčený
	local world = Config.Worlds[profile.WorldIndex]
	if not profile.Worlds[world.Id] then
		profile.WorldIndex = 1
		profile.Barrier = 1
		profile.Power = 0
	end

	-- Titul, který už v configu není, spadne na základní
	local titleExists = false
	for _, title in Config.Titles do
		if title.Id == profile.Title then
			titleExists = true
			break
		end
	end
	if not titleExists then
		profile.Title = Config.Titles[1].Id
	end

	return profile
end

local function retry(label: string, fn: () -> any): (boolean, any)
	local waitSeconds = 1

	for attempt = 1, 4 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end

		warn(`[DataService] {label} selhalo (pokus {attempt}/4): {result}`)
		if attempt < 4 then
			task.wait(waitSeconds)
			waitSeconds *= 2
		end
	end

	return false, nil
end

local function key(player: Player): string
	return `player_{player.UserId}`
end

function DataService.load(player: Player): Profile
	if profiles[player] then
		return profiles[player]
	end

	local ok, saved = retry("načtení profilu", function()
		return store:GetAsync(key(player))
	end)

	local profile: Profile
	if ok then
		profile = reconcile(saved or defaultProfile())
		profile._canSave = true
	else
		profile = reconcile(defaultProfile())
		profile._canSave = false
		warn(`[DataService] {player.Name} hraje bez ukládání — DataStore nedostupný.`)
	end

	profile._sessionStart = os.clock()
	profile._dirty = false
	profiles[player] = profile

	return profile
end

function DataService.get(player: Player): Profile?
	return profiles[player]
end

function DataService.await(player: Player, timeout: number?): Profile?
	local deadline = os.clock() + (timeout or 15)
	while not profiles[player] and os.clock() < deadline do
		if not player.Parent then
			return nil
		end
		task.wait(0.1)
	end
	return profiles[player]
end

function DataService.markDirty(player: Player)
	local profile = profiles[player]
	if profile then
		profile._dirty = true
	end
end

function DataService.playtime(player: Player): number
	local profile = profiles[player]
	if not profile then
		return 0
	end
	local live = if profile._sessionStart then os.clock() - profile._sessionStart else 0
	return profile.Playtime + live
end

function DataService.save(player: Player, isFinal: boolean?): boolean
	local profile = profiles[player]
	if not profile or not profile._canSave then
		return false
	end

	if profile._sessionStart then
		profile.Playtime += os.clock() - profile._sessionStart
		profile._sessionStart = os.clock()
	end

	if isFinal then
		profile.LeftAt = os.time()
	end

	local payload = {}
	for field, value in profile :: any do
		if not string.match(field, "^_") then
			payload[field] = value
		end
	end

	local ok = retry("uložení profilu", function()
		store:UpdateAsync(key(player), function()
			return payload
		end)
		return true
	end)

	if ok then
		profile._dirty = false
	elseif isFinal then
		warn(`[DataService] Profil {player.Name} se nepodařilo uložit při odchodu.`)
	end

	return ok
end

function DataService.release(player: Player)
	DataService.save(player, true)
	profiles[player] = nil
end

function DataService.start()
	task.spawn(function()
		while true do
			task.wait(120)
			for player, profile in profiles do
				if profile._dirty then
					task.spawn(DataService.save, player)
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(DataService.release)

	game:BindToClose(function()
		if RunService:IsStudio() then
			return
		end

		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				DataService.save(player, true)
				pending -= 1
			end)
		end

		local deadline = os.clock() + 20
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService

--!strict
--[[
	DataService — načítání a ukládání profilu hráče.

	Profil drží úplně všechno, co grind vyprodukuje: peníze, XP, level,
	vlastněné nože a materiály, úrovně vylepšení, rebirthy a odehraný čas.

	Odolnost:
	  * načtení i uložení běží přes pcall s exponenciálním backoffem,
	  * když DataStore selže (typicky Studio bez API access), hra běží dál
	    s výchozím profilem, ale ukládání se pro tu session vypne,
	    aby se hráči nepřepsal skutečný postup nulami,
	  * BindToClose uloží všechny hráče při vypnutí serveru.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

export type Profile = {
	Coins: number,
	Xp: number,
	Level: number,
	Tools: { [string]: boolean },
	EquippedTool: string,
	Objects: { [string]: boolean },
	EquippedObject: string,
	Upgrades: { [string]: number },
	Rebirths: number,
	Playtime: number, -- celkový odehraný čas v sekundách
	ClaimedRewards: { [string]: boolean }, -- klíč = počet minut jako string
	TotalStrikes: number,
	TotalDestroyed: number,

	-- runtime, neukládá se
	_dirty: boolean?,
	_canSave: boolean?,
	_sessionStart: number?,
}

local DataService = {}

local store = DataStoreService:GetDataStore(Config.Data.StoreName)
local profiles: { [Player]: Profile } = {}
local loading: { [Player]: boolean } = {}

local function defaultProfile(): Profile
	return {
		Coins = 0,
		Xp = 0,
		Level = 1,
		Tools = { [Config.Tools[1].Id] = true },
		EquippedTool = Config.Tools[1].Id,
		Objects = { [Config.Objects[1].Id] = true },
		EquippedObject = Config.Objects[1].Id,
		Upgrades = {},
		Rebirths = 0,
		Playtime = 0,
		ClaimedRewards = {},
		TotalStrikes = 0,
		TotalDestroyed = 0,
	}
end

-- Doplní chybějící klíče (po update hry mají staré profily starý tvar)
local function reconcile(profile: any): Profile
	local template = defaultProfile()

	for key, value in template do
		if profile[key] == nil then
			profile[key] = value
		end
	end

	-- Nástroj/materiál smazaný z configu by hru rozbil -> spadni na první
	if not Config.tool(profile.EquippedTool) then
		profile.EquippedTool = Config.Tools[1].Id
	end
	if not Config.object(profile.EquippedObject) then
		profile.EquippedObject = Config.Objects[1].Id
	end

	-- Startovní vybavení má hráč vždycky
	profile.Tools[Config.Tools[1].Id] = true
	profile.Objects[Config.Objects[1].Id] = true

	-- Nasazené věci musí být i vlastněné
	profile.Tools[profile.EquippedTool] = true
	profile.Objects[profile.EquippedObject] = true

	return profile
end

local function retry<T>(label: string, fn: () -> T): (boolean, T?)
	local delaySeconds = 1

	for attempt = 1, Config.Data.MaxRetries do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end

		warn(`[DataService] {label} selhalo (pokus {attempt}/{Config.Data.MaxRetries}): {result}`)
		if attempt < Config.Data.MaxRetries then
			task.wait(delaySeconds)
			delaySeconds *= 2
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

	loading[player] = true

	local ok, saved = retry("načtení profilu", function()
		return store:GetAsync(key(player))
	end)

	local profile: Profile
	if ok then
		profile = reconcile(saved or defaultProfile())
		profile._canSave = true
	else
		-- Nepodařilo se načíst: hraj, ale neukládej (jinak přepíšeme postup).
		profile = reconcile(defaultProfile())
		profile._canSave = false
		warn(`[DataService] {player.Name} hraje bez ukládání — DataStore nedostupný.`)
	end

	profile._sessionStart = os.clock()
	profile._dirty = false

	profiles[player] = profile
	loading[player] = nil
	return profile
end

function DataService.get(player: Player): Profile?
	return profiles[player]
end

-- Počká, dokud profil nedorazí (pro služby, které startují souběžně)
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

function DataService.save(player: Player, isFinal: boolean?): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end

	if not profile._canSave then
		return false
	end

	-- Odehraný čas se dopočítá až při ukládání
	if profile._sessionStart then
		profile.Playtime += os.clock() - profile._sessionStart
		profile._sessionStart = os.clock()
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
	-- Autosave
	task.spawn(function()
		while true do
			task.wait(Config.Data.AutosaveInterval)
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

-- Aktuální odehraný čas včetně probíhající session
function DataService.playtime(player: Player): number
	local profile = profiles[player]
	if not profile then
		return 0
	end
	local live = if profile._sessionStart then os.clock() - profile._sessionStart else 0
	return profile.Playtime + live
end

return DataService

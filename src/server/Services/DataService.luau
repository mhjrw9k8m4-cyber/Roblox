--!strict
--[[
	DataService — načítání a ukládání profilu.

	Odolnost:
	  * načtení i uložení běží přes pcall s exponenciálním backoffem,
	  * když DataStore selže (typicky Studio bez API access), hra běží dál,
	    ale ukládání se pro tu session vypne — jinak by se hráči přepsal
	    skutečný postup výchozími nulami,
	  * BindToClose uloží všechny hráče při vypnutí serveru.

	SESSION LOCKING
	Nejčastější příčina ztráty dat v Robloxu je, když stejný profil běží
	na dvou serverech naráz: oba si ho načtou, oba ho uloží a ten pomalejší
	přepíše ten novější. Stačí, aby hráč rychle přeskočil mezi servery.

	Řešení: při načtení se do klíče **ve stejném UpdateAsync** zapíše zámek
	s JobId serveru a časem. Jiný server pak vidí, že profil je zabraný,
	a nenačte ho. Zámek se během hraní obnovuje, takže dlouhé sezení
	nezestárne, a při odchodu se uvolní.

	Když server spadne, zámek zůstane viset — proto má časový limit.
	Po jeho vypršení se považuje za mrtvý a další server ho může převzít.

	Uložený čas odchodu slouží k offline výdělkům, proto se ukládá
	`LeftAt` jako os.time() (reálný čas), ne os.clock().
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Live = require(Shared.Live)
local Lock = require(Shared.Lock)

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

	-- Squishy hračky
	Squishies: { [string]: number }, -- id -> počet kusů
	Variants: { [string]: number }, -- id -> varianta (obyčejná/zlatá/duhová)
	Collection: { [string]: boolean }, -- vyzvednuté milníky sbírky
	Held: { string }, -- co má hráč u sebe; první je v ruce
	Squeezes: number,

	--[[
		Vyřízené účtenky za vývojářské produkty.

		Roblox stejnou účtenku doručí i víckrát — proto v ní vůbec je
		`PurchaseId`. Bez tohohle seznamu by hráč za jeden nákup dostal
		gemy dvakrát i třikrát, a poznalo by se to až na číslech, která
		nesedí s tržbami.

		Je to seznam s pevným stropem, ne rostoucí tabulka: Roblox
		opakuje doručení v řádu minut, takže si stačí pamatovat poslední
		hrstku. Neomezený seznam by profil nafukoval do konce života účtu.
	]]
	Receipts: { string },

	--[[
		Koho hráč přivedl. Odměna za pozvání je jednou za člověka —
		bez tohohle by stačilo, aby kamarád odešel a přišel znovu.
	]]
	Referred: { [string]: boolean },

	-- Placené a milníky
	Passes: { [string]: boolean },
	Badges: { [string]: boolean },
	Spent: number, -- kolik peněz hráč celkem utratil (pro úkoly)
	Settings: { [string]: any },

	-- runtime, neukládá se
	_dirty: boolean?,
	_canSave: boolean?,
	_sessionStart: number?,
	_lastLockAt: number?,
	_lockReason: string?,
}

local DataService = {}

local store = DataStoreService:GetDataStore(Config.GameName .. "_v1")
local profiles: { [Player]: Profile } = {}

-- Kolikrát se zkusí počkat, než to vzdáme a pustíme hráče bez ukládání
local LOCK_ATTEMPTS = 4

local JOB_ID = Lock.jobId(game.JobId, os.clock())


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

		-- Úplně první hračku dostane každý zadarmo; která to je, říká `Live.Starter`
		Squishies = { [Live.Starter] = 1 },
		--[[
			Startovní hračka je vždycky obyčejná. Losovat ji by znamenalo,
			že jeden hráč ze sta začíná se trojnásobkem — a to je rozdíl,
			který se v prvních deseti minutách pozná.
		]]
		Variants = { [Live.Starter] = 1 },
		Collection = {},
		Held = { Live.Starter },
		Squeezes = 0,

		Receipts = {},
		Referred = {},

		Passes = {},
		Badges = {},
		Spent = 0,
		Laps = {},
		Perks = {},
		Cosmetics = { Trail = "none", Aura = "none", Skin = "none" },
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

	-- U sebe nesmí mít víc, než kolik vlastní — jinak by po smazání
	-- hračky z configu zůstal viset neplatný odkaz.
	local held = {}
	for _, id in profile.Held do
		if (profile.Squishies[id] or 0) > 0 then
			table.insert(held, id)
		end
	end
	profile.Held = held

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

--[[
	Načte profil a ve stejném zápisu si na klíč vezme zámek.

	Vrací i důvod, proč se případně nepodařilo — volající tak může hráči
	říct, co se děje, místo aby mu tiše vypnul ukládání.
]]
local function claim(player: Player): (boolean, any, string?)
	local key = `player_{player.UserId}`

	for attempt = 1, LOCK_ATTEMPTS do
		local blocked = false
		local loaded: any = nil

		local ok, err = pcall(function()
			store:UpdateAsync(key, function(raw)
				local record = Lock.toRecord(raw)
				local now = os.time()

				-- Zabráno jiným živým serverem: zápis se zruší vrácením nil
				if Lock.heldByOther(record, JOB_ID, now) then
					blocked = true
					return nil
				end

				blocked = false
				loaded = record.Data
				record.Lock = Lock.stamp(JOB_ID, now)
				return record
			end)
		end)

		if not ok then
			-- Strop na čekání: bez něj by čtyři chyby po sobě znamenaly
			-- půl minuty, po kterou hráč kouká na loading screen.
			warn(`[DataService] Načtení {player.Name} selhalo (pokus {attempt}): {err}`)
			task.wait(math.min(2 ^ attempt, 4))
			continue
		end

		if not blocked then
			return true, loaded, nil
		end

		-- Druhý server profil možná právě ukládá a pouští; chvíli počkáme
		warn(`[DataService] Profil {player.Name} drží jiný server, čekám (pokus {attempt}).`)
		task.wait(2.5)
	end

	return false, nil, "Your data is still open on another server."
end

function DataService.load(player: Player): Profile
	if profiles[player] then
		return profiles[player]
	end

	local claimed, saved, reason = claim(player)

	local profile: Profile
	if claimed then
		profile = reconcile(saved or defaultProfile())
		profile._canSave = true
	else
		--[[
			Nezískali jsme zámek. Hráč hraje, ale neukládá — přepsat cizí
			živé sezení výchozími hodnotami by bylo horší než nic neuložit.
		]]
		profile = reconcile(defaultProfile())
		profile._canSave = false
		profile._lockReason = reason
		warn(`[DataService] {player.Name} hraje bez ukládání: {reason}`)
	end

	profile._sessionStart = os.clock()
	profile._lastLockAt = os.time()
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

--[[
	Uloží profil a zároveň obnoví zámek.

	`isFinal` zámek naopak uvolní — hráč odchází a další server má mít
	profil hned k dispozici, ne čekat na vypršení.

	Zápis je pořád `UpdateAsync`, protože musí zkontrolovat, že zámek mezitím
	nepřevzal někdo jiný. Kdybychom slepě přepsali `SetAsync`em, vracíme se
	přesně k té chybě, kvůli které zámek existuje.
]]
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

	local stolen = false

	local ok = retry("uložení profilu", function()
		store:UpdateAsync(`player_{player.UserId}`, function(raw)
			local record = Lock.toRecord(raw)

			--[[
				Zámek mezitím převzal jiný server (typicky proto, že tenhle
				na chvíli zamrzl a zámek zestaral). Zápis se zruší — jeho
				data jsou novější než naše.
			]]
			if Lock.heldByOther(record, JOB_ID, os.time()) then
				stolen = true
				return nil
			end

			record.Data = payload
			record.Lock = if isFinal then nil else Lock.stamp(JOB_ID, os.time())
			return record
		end)
		return true
	end)

	if stolen then
		profile._canSave = false
		warn(`[DataService] Zámek {player.Name} převzal jiný server, ukládání zastaveno.`)
		return false
	end

	if ok then
		profile._dirty = false
		profile._lastLockAt = os.time()
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
	--[[
		Tep. Ukládá změněné profily a hlavně obnovuje zámek — bez toho by
		dlouhé sezení po `Lock.StaleSeconds` vypadalo jako mrtvé a jiný
		server by profil převzal zpod běžícího hráče.

		Proto se ukládá i profil, který se nezměnil: samotné obnovení zámku
		je zápis navíc a spojit to do jednoho je levnější.
	]]
	task.spawn(function()
		while true do
			task.wait(Lock.RefreshSeconds)

			for player, profile in profiles do
				if not profile._canSave then
					continue
				end

				local stale = Lock.needsRefresh(profile._lastLockAt, os.time())
				if profile._dirty or stale then
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

--!strict
--[[
	RetentionService — denní odměny se sérií, denní úkoly a kódy.

	Proč zrovna tyhle tři: Roblox od konce roku 2025 řadí hry podle toho,
	jestli se hráč vrátí druhý den a během týdne, ne podle počtu lidí
	online. Denní odměna dává důvod se vrátit zítra, úkoly prodlužují dnešní
	sezení a kód přivede zpátky každého, kdo uvidí nové video.

	Dvě série běží vedle sebe (přihlášení a splněné úkoly) schválně —
	dvě smyčky drží hráče líp než jedna a když jednu přeruší, druhá
	ho pořád má čím vrátit.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Combo = require(Shared.Combo)
local Live = require(Shared.Live)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local Guard = require(script.Parent.GuardService)
local GameService = require(script.Parent.GameService)

local RetentionService = {}

type Result = { Ok: boolean, Message: string? }

local function fail(message: string): Result
	return { Ok = false, Message = message }
end

local function succeed(message: string?): Result
	return { Ok = true, Message = message }
end

local function notify(player: Player, text: string, kind: string, sound: string?)
	Remotes.Notify:FireClient(player, { Text = text, Kind = kind, Sound = sound })
end

--[[
	Index dne. Počítá se z UTC, ne z lokálního času hráče — jinak by si
	posunem časového pásma šlo vzít odměnu dvakrát.
]]
local function dayIndex(now: number?): number
	return math.floor((now or os.time()) / 86400)
end

RetentionService.dayIndex = dayIndex

-- Denní odměna ----------------------------------------------------------------

--[[
	Vrátí stav kolotoče: který den je na řadě, jestli je odměna k dispozici
	a kolik sekund zbývá do dalšího dne.
]]
function RetentionService.dailyState(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return nil
	end

	local today = dayIndex()
	local claimedToday = profile.DailyClaimedOn == today

	-- Vynechaný den sérii shodí zpátky na první
	local nextDay = profile.DailyDay
	if not claimedToday then
		if profile.DailyClaimedOn == today - 1 then
			nextDay = profile.DailyDay % #Live.Daily + 1
		else
			nextDay = 1
		end
	end

	local entry = Live.Daily[math.clamp(nextDay, 1, #Live.Daily)]
	local coins = math.floor(Economy.coinsPerSecond(profile, os.time()) * entry.CoinSeconds)

	return {
		Day = nextDay,
		Claimed = claimedToday,
		Coins = math.max(coins, 100),
		Gems = entry.Gems,
		Squishy = entry.Squishy,
		SecondsToNext = (today + 1) * 86400 - os.time(),
		Streak = profile.DailyDay,
	}
end

function RetentionService.claimDaily(player: Player): Result
	local profile = DataService.get(player)
	if not profile then
		return fail("Profile not ready.")
	end

	local state = RetentionService.dailyState(player)
	if not state or state.Claimed then
		return fail("Already claimed today. Come back tomorrow!")
	end

	profile.DailyDay = state.Day
	profile.DailyClaimedOn = dayIndex()
	profile.Coins += state.Coins
	profile.Gems += state.Gems
	DataService.markDirty(player)
	DataService.save(player)

	local text = `Day {state.Day} reward: +{Format.short(state.Coins)} 💰  +{state.Gems} 💎`
	--[[
		Sedmý den dává hračku, kterou si nejde koupit. To je celý smysl
		streaku: musí za ním být něco, co se nedá obejít mincemi.
	]]
	if state.Squishy then
		local SquishyService = require(script.Parent.SquishyService)
		if SquishyService.grant(player, state.Squishy) then
			local squishy = Live.squishy(state.Squishy)
			text ..= `  +{squishy and squishy.Name or state.Squishy}!`
		end
	end

	GameService.pushProfile(player)
	RetentionService.push(player)
	notify(player, text, "success", "Purchase")

	return succeed()
end

-- Denní úkoly -------------------------------------------------------------------

--[[
	Vygeneruje tři úkoly na dnešek. Losuje se deterministicky z indexu dne
	a UserId, takže hráč dostane pokaždé jinou trojici, ale při restartu
	serveru se mu nezmění zadání pod rukama.
]]
local function rollQuests(player: Player, profile: any)
	local today = dayIndex()
	local random = Random.new(today * 7919 + player.UserId % 100000)

	local pool = table.clone(Live.Quests)
	local quests = {}

	for _ = 1, math.min(Live.QuestsPerDay, #pool) do
		local pick = table.remove(pool, random:NextInteger(1, #pool))
		if not pick then
			break
		end

		-- Cíl roste s postupem, jinak je zadání v šestém světě triviální
		local scale = 1 + (profile.WorldIndex - 1) * pick.Scale
		local target = math.max(math.floor(pick.Base * scale), 1)

		--[[
			Řetěz má strop (Combo.Max), takže cíl nad ním by byl
			nesplnitelný — a hráč by celý den koukal na úkol, který
			nejde dodělat. Strop se drží tady, ne v `Live`: kdo tam
			bude ladit čísla, na tenhle detail nemá myslet.
		]]
		if pick.Type == "combo" then
			target = math.min(target, Combo.Max)
		end

		table.insert(quests, {
			Id = pick.Id,
			Target = target,
			Progress = 0,
			Claimed = false,
		})
	end

	profile.QuestDay = today
	profile.Quests = quests
	DataService.markDirty(player)
end

function RetentionService.ensureQuests(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end

	if profile.QuestDay ~= dayIndex() or #profile.Quests == 0 then
		-- Vynechaný den shodí questovou sérii
		if profile.QuestDay ~= dayIndex() - 1 then
			profile.QuestStreak = 0
		end
		rollQuests(player, profile)
	end
end

--[[
	Posune postup v úkolu daného typu. Volá se z herní smyčky —
	GameService při průrazu, ShopService při nákupu a tak dál.
]]
function RetentionService.progress(player: Player, questType: string, amount: number)
	local profile = DataService.get(player)
	if not profile or amount <= 0 then
		return
	end

	local changed = false

	for _, quest in profile.Quests do
		local definition = Live.quest(quest.Id)
		if definition and definition.Type == questType and not quest.Claimed then
			if quest.Progress < quest.Target then
				quest.Progress = math.min(quest.Progress + amount, quest.Target)
				changed = true
			end
		end
	end

	if changed then
		DataService.markDirty(player)
	end
end

--[[
	Zápis "dosáhl jsi hodnoty N", ne "přidej N".

	Úkol na combo je maximum, ne součet: kdyby se sečítal, splnil by ho
	i ten, kdo sbírá pomalu a řetěz mu pořád padá — což je přesně naopak,
	než co má úkol učit.
]]
function RetentionService.reach(player: Player, questType: string, value: number)
	local profile = DataService.get(player)
	if not profile or value <= 0 then
		return
	end

	local changed = false

	for _, quest in profile.Quests do
		local definition = Live.quest(quest.Id)
		if definition and definition.Type == questType and not quest.Claimed then
			local capped = math.min(value, quest.Target)
			if capped > quest.Progress then
				quest.Progress = capped
				changed = true
			end
		end
	end

	if changed then
		DataService.markDirty(player)
	end
end

function RetentionService.claimQuest(player: Player, questId: string): Result
	local profile = DataService.get(player)
	if not profile or typeof(questId) ~= "string" then
		return fail("Profile not ready.")
	end

	for _, quest in profile.Quests do
		if quest.Id ~= questId then
			continue
		end
		if quest.Claimed then
			return fail("Already claimed.")
		end
		if quest.Progress < quest.Target then
			return fail("Not finished yet.")
		end

		local definition = Live.quest(questId)
		quest.Claimed = true
		profile.Gems += definition.Gems
		DataService.markDirty(player)

		-- Bonus za kompletní den drží druhou sérii
		local allDone = true
		for _, other in profile.Quests do
			if not other.Claimed then
				allDone = false
				break
			end
		end

		if allDone then
			profile.QuestStreak += 1
			profile.Gems += Live.QuestStreakGems
			notify(
				player,
				`All quests done! Streak {profile.QuestStreak} · +{Live.QuestStreakGems} 💎 bonus`,
				"success",
				"WorldClear"
			)
			DataService.save(player)
		else
			notify(player, `Quest complete: +{definition.Gems} 💎`, "success", "Purchase")
		end

		GameService.pushProfile(player)
		RetentionService.push(player)
		return succeed()
	end

	return fail("Unknown quest.")
end

-- Kódy -------------------------------------------------------------------------

function RetentionService.redeem(player: Player, input: string): Result
	local profile = DataService.get(player)
	if not profile or typeof(input) ~= "string" then
		return fail("Profile not ready.")
	end
	if #input == 0 or #input > 32 then
		return fail("Enter a code.")
	end

	local entry = Live.code(input)
	if not entry then
		return fail("Invalid code.")
	end
	if entry.Expires > 0 and os.time() > entry.Expires then
		return fail("This code has expired.")
	end
	if profile.Codes[entry.Code] then
		return fail("You already used this code.")
	end

	profile.Codes[entry.Code] = true
	profile.Coins += entry.Coins
	profile.Gems += entry.Gems
	DataService.markDirty(player)
	DataService.save(player)

	local parts = {}
	if entry.Coins > 0 then
		table.insert(parts, `+{Format.short(entry.Coins)} 💰`)
	end
	if entry.Gems > 0 then
		table.insert(parts, `+{entry.Gems} 💎`)
	end

	GameService.pushProfile(player)
	notify(player, `Code {entry.Code}: {table.concat(parts, "  ")}`, "success", "Purchase")

	return succeed()
end

-- Odeslání stavu klientovi ---------------------------------------------------------

function RetentionService.snapshot(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return nil
	end

	RetentionService.ensureQuests(player)

	local quests = {}
	for _, quest in profile.Quests do
		local definition = Live.quest(quest.Id)
		if definition then
			table.insert(quests, {
				Id = quest.Id,
				Text = (definition.Text:gsub("{target}", Format.short(quest.Target))),
				Progress = quest.Progress,
				Target = quest.Target,
				Claimed = quest.Claimed,
				Gems = definition.Gems,
			})
		end
	end

	--[[
		Ladder za sezení jde ven přes tabulku služby, ne přes lokální
		funkci: ta je definovaná až níž a `snapshot` by ji ve svém
		uzávěru neviděl.
	]]
	local session = RetentionService.sessionSeconds(player, profile)

	return {
		Daily = RetentionService.dailyState(player),
		Quests = quests,
		QuestStreak = profile.QuestStreak,
		StreakBonus = Live.QuestStreakGems,
		--[[
			Kolik sezení už běží a kolikátý stupeň je hotový. Panel
			z toho poskládá odpočet — bez něj by hráč o téhle smyčce
			věděl jen z hlášky, která už proběhla.
		]]
		Session = session,
		SessionTier = Live.playtimeReached(session),
	}
end

function RetentionService.push(player: Player)
	local snapshot = RetentionService.snapshot(player)
	if snapshot then
		Remotes.RetentionChanged:FireClient(player, snapshot)
	end
end

-- Odměny za délku sezení -------------------------------------------------------

--[[
	Kolikátý stupeň už hráč v tomhle sezení dostal.

	Drží se v paměti serveru, ne v profilu: smysl téhle smyčky je
	prodloužit TOHLE přihlášení. Kdyby se to ukládalo, vrátil by se hráč
	zítra k ladderu, který má dávno vyčerpaný, a mechanika by pro něj
	přestala existovat.
]]
local sessionTier: { [Player]: number } = {}

--[[
	Kolik sekund hráč v tomhle sezení hraje.

	`DataService.playtime` vrací odehraný čas CELKEM (i z minulých
	sezení), takže by veterán dostal všechny stupně naráz hned po
	přihlášení. Odečítá se proto to, co měl při příchodu.
]]
local function sessionSeconds(player: Player, profile: any): number
	local total = DataService.playtime(player)
	return math.max(total - (profile.Playtime or 0), 0)
end

RetentionService.sessionSeconds = sessionSeconds

--[[
	Udělí, co hráči za dobu v sezení náleží.

	Uděluje se automaticky, ne přes tlačítko. Tlačítko, které se objeví
	uprostřed běhu, hráč buď přehlédne, nebo kvůli němu musí zastavit —
	a zastavit se v téhle hře znamená přijít o řetěz.
]]
function RetentionService.checkPlaytime(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end

	local reached = Live.playtimeReached(sessionSeconds(player, profile))
	local given = sessionTier[player] or 0
	if reached <= given then
		return
	end

	local now = os.time()
	local coins = 0
	local gems = 0

	-- Přeskočené stupně se doplatí: hráč mohl být chvíli mimo okno tikání
	for index = given + 1, reached do
		local tier = Live.Playtime[index]
		coins += math.max(math.floor(Economy.coinsPerSecond(profile, now) * tier.IncomeSeconds), 100)
		gems += tier.Gems
	end

	sessionTier[player] = reached
	profile.Coins += coins
	profile.Gems += gems
	DataService.markDirty(player)
	GameService.pushProfile(player)

	local minutes = Live.Playtime[reached].Minutes
	notify(
		player,
		`{minutes} MINUTES! +{Format.short(coins)} 💰  +{gems} 💎`,
		"success",
		"Unlock"
	)
end

function RetentionService.start()
	--[[
		Ladder patří sezení, ne hráči. Bez tohohle by se po odpojení
		a návratu na stejný server pokračovalo tam, kde to skončilo.
	]]
	Players.PlayerRemoving:Connect(function(player)
		sessionTier[player] = nil
	end)

	Guard.wrapFunction("ClaimDaily", "Write", RetentionService.claimDaily)
	Guard.wrapFunction("ClaimQuest", "Write", RetentionService.claimQuest)
	-- Kódy se hádají hrubou silou, proto stejně přísně jako zápisy
	Guard.wrapFunction("RedeemCode", "Write", RetentionService.redeem)

	-- Postup v úkolech se posílá jen občas; po každém sebraném pickupu
	-- by to byl zbytečný provoz.
	task.spawn(function()
		while true do
			task.wait(6)
			for _, player in Players:GetPlayers() do
				if DataService.get(player) then
					RetentionService.checkPlaytime(player)
					RetentionService.push(player)
				end
			end
		end
	end)
end

return RetentionService

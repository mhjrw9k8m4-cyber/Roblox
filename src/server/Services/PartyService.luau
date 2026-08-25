--!strict
--[[
	PartyService — hraní s kamarády.

	Roblox od konce roku 2025 neřadí hry podle počtu hráčů online, ale
	podle toho, jestli se hráč VRÁTÍ — a jedním z měřených signálů je
	společné hraní. Hra, do které si lidé zvou kamarády, dostane víc míst
	v doporučování než hra se stejným počtem lidí, kteří sedí každý sám.

	V téhle hře dělá služba dvě věci:

	  * dokud je na serveru kamarád, sype hráči víc mincí — bonus musí
	    být na měně, ne na kosmetice, aby se vyplatilo počkat, než se
	    kamarád připojí,
	  * kdo někoho přivede, dostane gemy. Jednou za člověka: bez toho by
	    stačilo, aby kamarád odešel a přišel znovu.

	`IsFriendsWith` je síťové volání, takže se výsledek drží v paměti po
	dobu sezení. Ptát se na něj při každém připojení znovu by při plném
	serveru znamenalo desítky volání naráz.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Format = require(Shared.Format)
local Live = require(Shared.Live)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local GameService = require(script.Parent.GameService)

local PartyService = {}

--[[
	Kdo je s kým kamarád. Klíč je dvojice UserId seřazená od menšího,
	aby se stejná dvojice nezjišťovala dvakrát z každé strany.
]]
local friendship: { [string]: boolean } = {}

local function pairKey(a: number, b: number): string
	return if a < b then `{a}:{b}` else `{b}:{a}`
end

--[[
	Jsou to kamarádi? Chyba (výpadek sítě) se počítá jako "ne" a NEuloží
	se — příště se to zkusí znovu. Uložená chyba by dvojici označila jako
	cizí až do restartu serveru.
]]
local function areFriends(a: Player, b: Player): boolean
	local key = pairKey(a.UserId, b.UserId)
	local known = friendship[key]
	if known ~= nil then
		return known
	end

	local ok, result = pcall(function()
		return a:IsFriendsWith(b.UserId)
	end)

	if not ok then
		return false
	end

	friendship[key] = result
	return result
end

--[[
	Kolik kamarádů má hráč zrovna na serveru.
]]
function PartyService.countFriends(player: Player): number
	local count = 0
	for _, other in Players:GetPlayers() do
		if other ~= player and areFriends(player, other) then
			count += 1
		end
	end
	return count
end

--[[
	Přepočítá bonus všem. Volá se při příchodu i odchodu — odchod je
	stejně důležitý jako příchod, protože bonus musí zmizet ve chvíli,
	kdy kamarád odejde, ne až při dalším průrazu.
]]
function PartyService.refresh()
	for _, player in Players:GetPlayers() do
		local profile = DataService.get(player)
		if not profile then
			continue
		end

		local friends = PartyService.countFriends(player)
		local before = profile.Friends or 0
		if before == friends then
			continue
		end

		--[[
			`Friends` se schválně NEukládá. Je to stav serveru, ne
			majetek hráče; uložený by si ho hráč nesl na prázdný server
			a bonus za společné hraní by platil i pro toho, kdo hraje sám.
		]]
		profile.Friends = friends
		GameService.pushProfile(player)

		--[[
			Hlásí se jen PŘÍRŮSTEK. Když kamarád odejde, počet taky
			"změní", a bez téhle podmínky by hráč dostal gratulaci
			ve chvíli, kdy o bonus přišel.
		]]
		if friends > before then
			local bonus = math.floor(
				math.clamp(friends, 0, Live.Social.MaxFriends) * Live.Social.FriendBonus * 100
			)
			Remotes.Notify:FireClient(player, {
				Text = `{friends} friend{if friends == 1 then "" else "s"} here — +{bonus}% coins!`,
				Kind = "success",
				Sound = "Unlock",
			})
		end
	end
end

--[[
	Odměna za přivedeného hráče.

	`GetJoinData().referredByPlayerId` vyplní Roblox, když někdo přišel
	přes pozvánku do hry. Odměnu dostane ten, kdo pozval — a jen když je
	pořád na serveru; posílat gemy někomu, kdo je pryč, by znamenalo
	sahat na cizí profil mimo sezení.
]]
function PartyService.rewardReferral(player: Player)
	local ok, data = pcall(function()
		return player:GetJoinData()
	end)

	local referrer = ok and data and data.referredByPlayerId
	if typeof(referrer) ~= "number" or referrer == 0 then
		return
	end

	local host = Players:GetPlayerByUserId(referrer)
	if not host then
		return
	end

	local profile = DataService.get(host)
	if not profile then
		return
	end

	local key = tostring(player.UserId)
	if profile.Referred[key] then
		return
	end

	profile.Referred[key] = true
	profile.Gems += Live.Social.ReferralGems
	DataService.markDirty(host)
	GameService.pushProfile(host)

	Remotes.Notify:FireClient(host, {
		Text = `{player.DisplayName} joined from your invite! +{Format.short(Live.Social.ReferralGems)} 💎`,
		Kind = "success",
		Sound = "Rebirth",
	})
end

-- Společný průraz ---------------------------------------------------------------

--[[
	Kdo kdy kterou zeď rozbil. Klíč je svět a index zdi, takže se potkají
	jen ti, kdo stáli opravdu u té samé.

	Drží se jen poslední průraz na zeď. Delší historie by nepomohla:
	okno je pár vteřin a starší záznam je stejně mimo.
]]
local lastSmash: { [string]: { Player: Player, At: number } } = {}

--[[
	Ohlásí průraz a vrátí, s kým se hráč potkal.

	Vrací hráče, ne jen "ano/ne" — obě strany musí dostat bonus
	i hlášku, a ta druhá strana zeď rozbila o vteřinu dřív, takže se
	k ní odjinud nedostaneme.
]]
function PartyService.markSmash(player: Player, worldIndex: number, barrierIndex: number): Player?
	local key = `{worldIndex}:{barrierIndex}`
	local now = os.clock()
	local previous = lastSmash[key]

	lastSmash[key] = { Player = player, At = now }

	if not previous or previous.Player == player then
		return nil
	end
	if now - previous.At > Live.Social.TogetherSeconds then
		return nil
	end
	--[[
		Ten druhý mezitím mohl odejít. Připisovat mince hráči, který na
		serveru není, znamená sahat na profil mimo sezení.
	]]
	if not previous.Player.Parent then
		return nil
	end

	return previous.Player
end

--[[
	Odměna za společný průraz. Dostanou ji oba a oba se o tom dozvědí —
	bonus, o kterém ví jen jeden, druhého k ničemu nepřiměje.
]]
function PartyService.rewardTogether(player: Player, partner: Player, coins: number)
	local bonus = math.floor(coins * Live.Social.TogetherBonus)
	if bonus <= 0 then
		return
	end

	for _, pair in { { player, partner }, { partner, player } } do
		local who, other = pair[1], pair[2]
		local profile = DataService.get(who)
		if not profile then
			continue
		end

		profile.Coins += bonus
		DataService.markDirty(who)
		GameService.pushProfile(who)

		Remotes.Notify:FireClient(who, {
			Text = `TOGETHER with {other.DisplayName}! +{Format.short(bonus)} 💰`,
			Kind = "success",
			Sound = "Ready",
		})
	end
end

function PartyService.start()
	Players.PlayerAdded:Connect(function(player)
		--[[
			Profil ještě nemusí být načtený; `await` počká. Bez toho by
			nově příchozí bonus nedostal a musel by čekat na to, až se
			připojí někdo další.
		]]
		task.spawn(function()
			DataService.await(player, 20)
			PartyService.rewardReferral(player)
			PartyService.refresh()
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		--[[
			Dvojice s odcházejícím hráčem se zapomenou. Server běží týdny
			a bez úklidu by tabulka rostla s každým, kdo se kdy připojil.
		]]
		local mine = `{player.UserId}:`
		local suffix = `:{player.UserId}`
		for key in friendship do
			if string.sub(key, 1, #mine) == mine or string.sub(key, -#suffix) == suffix then
				friendship[key] = nil
			end
		end

		-- Záznam o průrazu odcházejícího hráče: jinak by se s ním
		-- "potkal" někdo, kdo přijde o vteřinu později
		for key, entry in lastSmash do
			if entry.Player == player then
				lastSmash[key] = nil
			end
		end

		task.defer(PartyService.refresh)
	end)

	PartyService.refresh()
end

return PartyService

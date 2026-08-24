--!strict
--[[
	TradeService — obchod mezi dvěma hráči na jednom serveru.

	Záměrně jen v rámci serveru. Obchod přes servery by potřeboval
	rozhodčího nad DataStore a otevřel by celou třídu chyb, kde jedna
	strana zapíše a druhá ne. Tady jsou oba profily v paměti pod zámkem
	tohohle serveru, takže výměna může proběhnout naráz.

	Veškerý výpočet je v `Shared.Trade` jako čisté funkce — tenhle soubor
	řeší jen stavy, oprávnění a síť. Díky tomu jde ta část, kde chyba
	znamená duplikaci itemů, otestovat mimo hru.

	Pravidla proti podvodům:
	  * jakákoliv změna nabídky ruší obě potvrzení,
	  * vlastnictví se ověřuje ZNOVU v okamžiku výměny, ne při vkládání,
	  * hráč může mít otevřený jen jeden obchod,
	  * odchod, nečinnost i změna světa obchod zruší.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Live = require(Shared.Live)
local Remotes = require(Shared.Remotes)
local Trade = require(Shared.Trade)

local DataService = require(script.Parent.DataService)
local GameService = require(script.Parent.GameService)

local TradeService = {}

type Session = {
	A: Player,
	B: Player,
	OfferA: Trade.Offer,
	OfferB: Trade.Offer,
	ConfirmA: boolean,
	ConfirmB: boolean,
	TouchedAt: number,
	Committing: boolean,
}

-- Jeden záznam sdílí obě strany, klíčovaný oběma hráči
local sessions: { [Player]: Session } = {}
local invites: { [Player]: { From: Player, At: number } } = {}

local function notify(player: Player, text: string, kind: string)
	Remotes.Notify:FireClient(player, { Text = text, Kind = kind })
end

local function other(session: Session, player: Player): Player
	return if session.A == player then session.B else session.A
end

--[[
	Nabídka očima jednoho hráče. Klient nemusí vědět, kdo je A a kdo B —
	dostane vždycky "moje" a "jeho".
]]
local function describe(session: Session?, player: Player)
	if not session then
		return { Active = false }
	end

	local mine = if session.A == player then session.OfferA else session.OfferB
	local theirs = if session.A == player then session.OfferB else session.OfferA

	local function toList(offer: Trade.Offer)
		local list = {}
		for petId, count in offer do
			local pet = Live.pet(petId)
			if pet then
				table.insert(list, {
					Id = petId,
					Name = pet.Name,
					Rarity = pet.Rarity,
					Shape = pet.Shape,
					Power = pet.Power,
					Count = count,
				})
			end
		end
		table.sort(list, function(left, right)
			return left.Power > right.Power
		end)
		return list
	end

	return {
		Active = true,
		Partner = other(session, player).DisplayName,
		Mine = toList(mine),
		Theirs = toList(theirs),
		ConfirmedMine = if session.A == player then session.ConfirmA else session.ConfirmB,
		ConfirmedTheirs = if session.A == player then session.ConfirmB else session.ConfirmA,
		SecondsLeft = math.max(Trade.TimeoutSeconds - (os.time() - session.TouchedAt), 0),
	}
end

local function push(session: Session)
	Remotes.TradeChanged:FireClient(session.A, describe(session, session.A))
	Remotes.TradeChanged:FireClient(session.B, describe(session, session.B))
end

local function close(session: Session, reason: string?)
	sessions[session.A] = nil
	sessions[session.B] = nil

	for _, player in { session.A, session.B } do
		Remotes.TradeChanged:FireClient(player, { Active = false })
		if reason then
			notify(player, reason, "warn")
		end
	end
end

-- Žádosti -------------------------------------------------------------------

function TradeService.request(player: Player, targetUserId: number)
	if sessions[player] or typeof(targetUserId) ~= "number" then
		return
	end

	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target == player then
		return
	end
	if sessions[target] then
		notify(player, `{target.DisplayName} is already trading.`, "warn")
		return
	end

	invites[target] = { From = player, At = os.time() }
	Remotes.TradeInvite:FireClient(target, {
		UserId = player.UserId,
		Name = player.DisplayName,
	})
	notify(player, `Trade request sent to {target.DisplayName}.`, "info")
end

function TradeService.respond(player: Player, accept: boolean)
	local invite = invites[player]
	invites[player] = nil

	if not invite then
		return
	end

	local from = invite.From
	if not from.Parent then
		return
	end

	if not accept then
		notify(from, `{player.DisplayName} declined.`, "warn")
		return
	end

	-- Mezi pozvánkou a přijetím se mohl kdokoliv z nich pustit do jiného obchodu
	if sessions[player] or sessions[from] then
		notify(player, "That trade is no longer available.", "warn")
		return
	end

	local session: Session = {
		A = from,
		B = player,
		OfferA = {},
		OfferB = {},
		ConfirmA = false,
		ConfirmB = false,
		TouchedAt = os.time(),
		Committing = false,
	}

	sessions[from] = session
	sessions[player] = session
	push(session)
end

-- Nabídka ---------------------------------------------------------------------

function TradeService.offer(player: Player, petId: string, adding: boolean)
	local session = sessions[player]
	if not session or session.Committing or typeof(petId) ~= "string" then
		return
	end

	local profile = DataService.get(player)
	if not profile then
		return
	end

	local isA = session.A == player
	local current = if isA then session.OfferA else session.OfferB

	local next: Trade.Offer
	if adding then
		local allowed, reason = Trade.canAdd(profile.Pets, current, petId)
		if not allowed then
			notify(player, reason or "Cannot add that.", "warn")
			return
		end
		next = Trade.add(current, petId)
	else
		next = Trade.remove(current, petId)
	end

	if isA then
		session.OfferA = next
	else
		session.OfferB = next
	end

	-- Každá změna shodí obě potvrzení; jinak jde vyměnit obsah po potvrzení
	Trade.resetConfirmations(session)
	session.TouchedAt = os.time()
	push(session)
end

-- Potvrzení a výměna ----------------------------------------------------------------

--[[
	Provede výměnu.

	Vlastnictví se ověřuje TEĎ, ne při vkládání do nabídky: mezi nabídnutím
	a potvrzením mohl hráč peta sloučit nebo vylíhnout něco jiného.

	Obě strany se zapisují naráz a teprve pak se ukládají. Kdyby se zápis
	dělal po jednom a mezi tím něco spadlo, jedna strana by o pety přišla
	a druhá by je nedostala.
]]
local function commit(session: Session)
	session.Committing = true

	local profileA = DataService.get(session.A)
	local profileB = DataService.get(session.B)

	if not profileA or not profileB then
		close(session, "Trade cancelled — a profile is not loaded.")
		return
	end

	local okA, reasonA = Trade.validate(profileA.Pets, session.OfferA)
	local okB, reasonB = Trade.validate(profileB.Pets, session.OfferB)

	if not okA or not okB then
		close(session, reasonA or reasonB or "Trade cancelled.")
		return
	end

	local nextA, nextB = Trade.apply(profileA.Pets, session.OfferA, profileB.Pets, session.OfferB)

	profileA.Pets = nextA
	profileB.Pets = nextB
	profileA.EquippedPets = Trade.pruneEquipped(nextA, profileA.EquippedPets)
	profileB.EquippedPets = Trade.pruneEquipped(nextB, profileB.EquippedPets)

	DataService.markDirty(session.A)
	DataService.markDirty(session.B)

	-- Uložit hned: obchod je jediná operace, kde si hráči mění majetek
	-- navzájem, a ztratit ji při pádu serveru by bylo nejhorší možné
	DataService.save(session.A)
	DataService.save(session.B)

	GameService.pushProfile(session.A)
	GameService.pushProfile(session.B)

	for _, player in { session.A, session.B } do
		notify(player, "Trade complete!", "success")
	end

	close(session, nil)
end

function TradeService.confirm(player: Player)
	local session = sessions[player]
	if not session or session.Committing then
		return
	end

	if session.A == player then
		session.ConfirmA = true
	else
		session.ConfirmB = true
	end

	session.TouchedAt = os.time()

	if Trade.bothConfirmed(session) then
		commit(session)
	else
		push(session)
	end
end

function TradeService.cancel(player: Player, reason: string?)
	local session = sessions[player]
	if not session then
		return
	end
	close(session, reason or `{player.DisplayName} cancelled the trade.`)
end

-- Seznam hráčů, kterým jde poslat žádost
function TradeService.candidates(player: Player)
	local list = {}

	for _, other in Players:GetPlayers() do
		if other ~= player and not sessions[other] then
			table.insert(list, { UserId = other.UserId, Name = other.DisplayName })
		end
	end

	return list
end

function TradeService.start()
	Remotes.TradeRequest.OnServerEvent:Connect(function(player, userId)
		TradeService.request(player, userId)
	end)

	Remotes.TradeRespond.OnServerEvent:Connect(function(player, accept)
		TradeService.respond(player, accept == true)
	end)

	Remotes.TradeOffer.OnServerEvent:Connect(function(player, petId, adding)
		TradeService.offer(player, petId, adding == true)
	end)

	Remotes.TradeConfirm.OnServerEvent:Connect(function(player)
		TradeService.confirm(player)
	end)

	Remotes.TradeCancel.OnServerEvent:Connect(function(player)
		TradeService.cancel(player)
	end)

	Remotes.TradeCandidates.OnServerInvoke = function(player)
		return TradeService.candidates(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		invites[player] = nil
		TradeService.cancel(player, "The other player left.")
	end)

	-- Nečinný obchod spadne sám; jinak by zablokoval oběma stranám další
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.time()

			--[[
				Nejdřív posbírat, pak zavírat.

				Jeden obchod je v `sessions` pod dvěma klíči (oba hráči),
				takže `close` během iterace maže i klíč, na který se teprve
				přijde. Mazání cizích klíčů za běhu `next` je nedefinované
				chování — a zároveň by se stejný obchod zavíral dvakrát.
			]]
			local expired: { any } = {}
			local seen: { [any]: boolean } = {}

			for _, session in sessions do
				if seen[session] then
					continue
				end
				seen[session] = true

				if not session.Committing and now - session.TouchedAt > Trade.TimeoutSeconds then
					table.insert(expired, session)
				end
			end

			for _, session in expired do
				close(session, "Trade timed out.")
			end

			for player, invite in invites do
				if now - invite.At > 30 then
					invites[player] = nil
				end
			end
		end
	end)
end

return TradeService

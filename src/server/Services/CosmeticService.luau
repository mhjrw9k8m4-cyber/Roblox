--!strict
--[[
	CosmeticService — nasazování stop a aur.

	Replikace jde přes atributy na `Player`, ne přes remote. Atribut se
	sám dostane ke všem klientům, drží se i pro toho, kdo se připojí
	později, a klient si ho může kdykoliv přečíst — u broadcastu bychom
	museli řešit "kdo přišel po odeslání" ručně.

	Odemčení se nikde neukládá (viz `Shared.Cosmetics`), takže se ověřuje
	při každém nasazení znovu proti aktuálním statistikám. Kdo o rebirth
	nepřijde, o kus nepřijde ani po restartu serveru.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Cosmetics = require(Shared.Cosmetics)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local Guard = require(script.Parent.GuardService)

local CosmeticService = {}

-- Jméno atributu a klíč v profilu podle druhu. Klient čte přesně tyhle.
local ATTRIBUTE = {
	trail = "CosmeticTrail",
	aura = "CosmeticAura",
	skin = "CosmeticSkin",
}

local SLOT = {
	trail = "Trail",
	aura = "Aura",
	skin = "Skin",
}

local function equippedId(profile: any, kind: string): string
	local slot = profile.Cosmetics or {}
	return slot[SLOT[kind]] or "none"
end

--[[
	Přepíše atributy podle profilu.

	Volá se i po rebirthu a po vylíhnutí — kus, na který hráč zrovna
	dosáhl, tím ale nenasazujeme. Nasazuje se jen ručně; tohle jen
	sundá to, na co už nemá nárok (rebirth maže světy, takže kus
	vázaný na jejich počet může zmizet).
]]
function CosmeticService.apply(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end

	local playtime = DataService.playtime(player)
	local changed = false

	for kind, attribute in ATTRIBUTE do
		local id = equippedId(profile, kind)
		local item = Cosmetics.get(kind, id)

		if not item or not Cosmetics.unlocked(profile, item, playtime) then
			id = "none"
			profile.Cosmetics = profile.Cosmetics or {}
			profile.Cosmetics[SLOT[kind]] = "none"
			changed = true
		end

		player:SetAttribute(attribute, id)
	end

	if changed then
		DataService.markDirty(player)
	end
end

function CosmeticService.equip(player: Player, kind: string, id: string): boolean
	local profile = DataService.get(player)
	if not profile or typeof(kind) ~= "string" or typeof(id) ~= "string" then
		return false
	end
	if not Cosmetics.isKind(kind) then
		return false
	end

	local item = Cosmetics.get(kind, id)
	if not item then
		return false
	end
	if not Cosmetics.unlocked(profile, item, DataService.playtime(player)) then
		return false
	end

	profile.Cosmetics = profile.Cosmetics or {}
	profile.Cosmetics[SLOT[kind]] = id

	DataService.markDirty(player)
	player:SetAttribute(ATTRIBUTE[kind], id)

	require(script.Parent.GameService).pushProfile(player)
	return true
end

function CosmeticService.start()
	--[[
		Odemykání se počítá ze statistik, které rostou průběžně — hráč
		by jinak o novém kusu nevěděl, dokud panel sám neotevře.
		Pomalé tempo stačí: nejrychlejší podmínka je 25 průrazů.
	]]
	task.spawn(function()
		local seen: { [Player]: number } = {}

		while true do
			task.wait(20)

			for _, player in Players:GetPlayers() do
				local profile = DataService.get(player)
				if not profile then
					continue
				end

				local playtime = DataService.playtime(player)
				local total = 0
				for _, kind in Cosmetics.Kinds do
					total += Cosmetics.owned(profile, kind, playtime)
				end
				local before = seen[player]
				seen[player] = total

				if before and total > before then
					Remotes.Notify:FireClient(player, {
						Text = `New cosmetic unlocked! ({total - before}) — check the Style tab`,
						Kind = "success",
						Sound = "Unlock",
					})
				end
			end

			for player in seen do
				if player.Parent == nil then
					seen[player] = nil
				end
			end
		end
	end)

	Guard.wrapFunction("EquipCosmetic", "Cheap", function(player, payload)
		if typeof(payload) ~= "table" then
			return false
		end
		return CosmeticService.equip(player, payload.Kind, payload.Id)
	end)
end

return CosmeticService

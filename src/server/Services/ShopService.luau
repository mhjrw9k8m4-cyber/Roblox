--!strict
--[[
	ShopService — nákup a nasazení nožů, materiálů a vylepšení,
	plus rebirth.

	Každá funkce vrací `{ Ok: boolean, Message: string? }`, takže si
	klient nemusí nic domýšlet a rovnou zobrazí důvod odmítnutí.
	Veškerá kontrola ceny a podmínek je tady — klient je jen displej.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Remotes = require(Shared.Remotes)

local ASMRService = require(script.Parent.ASMRService)
local DataService = require(script.Parent.DataService)
local StationService = require(script.Parent.StationService)

local ShopService = {}

type Result = { Ok: boolean, Message: string? }

local function fail(message: string): Result
	return { Ok = false, Message = message }
end

local function succeed(message: string?): Result
	return { Ok = true, Message = message }
end

local function notify(player: Player, text: string, kind: string)
	Remotes.Notify:FireClient(player, { Text = text, Kind = kind })
end

-- Nože --------------------------------------------------------------------

function ShopService.buyTool(player: Player, id: string): Result
	local profile = DataService.get(player)
	if not profile or typeof(id) ~= "string" then
		return fail("Profil ještě není načtený.")
	end

	local allowed, reason = Economy.canUnlockTool(profile, id)
	if not allowed then
		return fail(reason or "Nelze koupit.")
	end

	local tool = Config.tool(id)
	profile.Coins -= tool.Price
	profile.Tools[id] = true
	profile.EquippedTool = id
	DataService.markDirty(player)

	ASMRService.pushProfile(player)
	notify(player, `Koupil sis {tool.Name}!`, "success")
	return succeed()
end

function ShopService.equipTool(player: Player, id: string): Result
	local profile = DataService.get(player)
	if not profile or typeof(id) ~= "string" then
		return fail("Profil ještě není načtený.")
	end
	if not profile.Tools[id] then
		return fail("Tenhle nůž nevlastníš.")
	end

	profile.EquippedTool = id
	DataService.markDirty(player)
	ASMRService.pushProfile(player)
	return succeed()
end

-- Materiály ---------------------------------------------------------------

function ShopService.buyObject(player: Player, id: string): Result
	local profile = DataService.get(player)
	if not profile or typeof(id) ~= "string" then
		return fail("Profil ještě není načtený.")
	end

	local allowed, reason = Economy.canUnlockObject(profile, id)
	if not allowed then
		return fail(reason or "Nelze koupit.")
	end

	local object = Config.object(id)
	profile.Coins -= object.Price
	profile.Objects[id] = true
	DataService.markDirty(player)

	ShopService.equipObject(player, id)
	notify(player, `Odemkl sis {object.Name}!`, "success")
	return succeed()
end

function ShopService.equipObject(player: Player, id: string): Result
	local profile = DataService.get(player)
	if not profile or typeof(id) ~= "string" then
		return fail("Profil ještě není načtený.")
	end
	if not profile.Objects[id] then
		return fail("Tenhle materiál nevlastníš.")
	end

	profile.EquippedObject = id
	DataService.markDirty(player)

	-- Nový materiál se objeví hned, ať hráč nečeká na dokončení starého
	local station = StationService.get(player)
	if station then
		StationService.spawnObject(station)
	end

	ASMRService.pushProfile(player)
	return succeed()
end

-- Vylepšení ---------------------------------------------------------------

function ShopService.buyUpgrade(player: Player, id: string): Result
	local profile = DataService.get(player)
	if not profile or typeof(id) ~= "string" then
		return fail("Profil ještě není načtený.")
	end

	local allowed, reason = Economy.canBuyUpgrade(profile, id)
	if not allowed then
		return fail(reason or "Nelze koupit.")
	end

	local level = profile.Upgrades[id] or 0
	local price = Config.upgradePrice(id, level) :: number

	profile.Coins -= price
	profile.Upgrades[id] = level + 1
	DataService.markDirty(player)

	-- Auto-řez mění rychlost smyčky, tu je potřeba přenastavit
	if id == "Auto" then
		ASMRService.refreshAutoLoop(player)
	end

	ASMRService.pushProfile(player)

	local upgrade = Config.upgrade(id)
	notify(player, `{upgrade.Name} → úroveň {level + 1}`, "success")
	return succeed()
end

-- Rebirth ------------------------------------------------------------------

function ShopService.rebirth(player: Player): Result
	local profile = DataService.get(player)
	if not profile then
		return fail("Profil ještě není načtený.")
	end

	local allowed, reason = Economy.canRebirth(profile)
	if not allowed then
		return fail(reason or "Zatím na rebirth nemáš.")
	end

	profile.Rebirths += 1
	profile.Coins = 0
	profile.Upgrades = {}

	-- Materiály se resetují na startovní, nože podle configu zůstávají
	profile.Objects = { [Config.Objects[1].Id] = true }
	profile.EquippedObject = Config.Objects[1].Id

	if not Config.Rebirth.KeepTools then
		profile.Tools = { [Config.Tools[1].Id] = true }
		profile.EquippedTool = Config.Tools[1].Id
	end

	DataService.markDirty(player)
	DataService.save(player)

	ASMRService.refreshAutoLoop(player)

	local station = StationService.get(player)
	if station then
		StationService.spawnObject(station)
	end

	ASMRService.pushProfile(player)

	local bonus = math.floor(Config.Rebirth.BonusPerRebirth * 100)
	notify(player, `Rebirth #{profile.Rebirths}! Trvale +{bonus} % ke všem výdělkům.`, "success")
	return succeed()
end

-- Napojení remote funkcí ---------------------------------------------------

function ShopService.start()
	Remotes.BuyTool.OnServerInvoke = function(player, id)
		return ShopService.buyTool(player, id)
	end

	Remotes.EquipTool.OnServerInvoke = function(player, id)
		return ShopService.equipTool(player, id)
	end

	Remotes.BuyObject.OnServerInvoke = function(player, id)
		return ShopService.buyObject(player, id)
	end

	Remotes.EquipObject.OnServerInvoke = function(player, id)
		return ShopService.equipObject(player, id)
	end

	Remotes.BuyUpgrade.OnServerInvoke = function(player, id)
		return ShopService.buyUpgrade(player, id)
	end

	Remotes.DoRebirth.OnServerInvoke = function(player)
		return ShopService.rebirth(player)
	end

	Remotes.GetProfile.OnServerInvoke = function(player)
		local profile = DataService.await(player, 20)
		if not profile then
			return nil
		end
		return ASMRService.serialize(player, profile)
	end
end

return ShopService

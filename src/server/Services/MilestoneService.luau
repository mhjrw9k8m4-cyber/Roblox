--!strict
--[[
	MilestoneService — hlášení velkých okamžiků celému serveru.

	Jeden remote pro tři různé události (rebirth, nový svět, vzácný pet),
	protože z pohledu klienta jsou to tři varianty téhož: někdo něčeho
	dosáhl a všichni to mají vidět.

	Proč to vůbec vysílat všem: v tomhle žánru je postup ostatních hlavní
	důvod, proč hráč zůstane. Bez toho hraje sám na prázdné mapě, i když
	je server plný.

	Filtr je schválně přísný — hlásí se jen to, co stojí čas nebo peníze.
	Kdyby se hlásil každý průraz, přestane si toho kdokoli všímat.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)

local MilestoneService = {}

type Announcement = {
	Kind: string,
	UserId: number,
	Who: string,
	Text: string,
	Big: string?,
	Color: Color3?,
}

local function send(payload: Announcement)
	Remotes.Milestone:FireAllClients(payload)
end

--[[
	Rebirth. `Big` je nápis přes obrazovku, `Text` proužek pro ostatní —
	dvě různé věty, protože "TY jsi to udělal" a "kdosi to udělal" se
	nedají napsat stejně.
]]
function MilestoneService.rebirth(player: Player, count: number)
	send({
		Kind = "rebirth",
		UserId = player.UserId,
		Who = player.DisplayName,
		Text = `{player.DisplayName} udělal REBIRTH #{count}`,
		Big = `REBIRTH #{count}`,
		Color = Config.Theme.Violet,
	})
end

--[[
	Odemčený svět. Hlásí se až od druhého světa výš — první dostane
	každý zadarmo a hlásit ho by znamenalo spam při každém příchodu.
]]
function MilestoneService.world(player: Player, world, index: number)
	if not world or index <= 1 then
		return
	end

	send({
		Kind = "world",
		UserId = player.UserId,
		Who = player.DisplayName,
		Text = `{player.DisplayName} odemkl {world.Name} za {Format.short(world.Price)}`,
		Big = `{string.upper(world.Name)} UNLOCKED`,
		Color = Config.Theme.Gold,
	})
end

--[[
	Vzácný pet. Běžné a vzácné se nehlásí — na plném serveru se líhne
	pořád něco a výpis by se nedal číst.
]]
function MilestoneService.pet(player: Player, pet, rarity)
	if not pet or not rarity or rarity.Weight > 10 then
		return
	end

	send({
		Kind = "pet",
		UserId = player.UserId,
		Who = player.DisplayName,
		Text = `{player.DisplayName} vylíhl {rarity.Name} {pet.Name}!`,
		Color = rarity.Color,
	})
end

return MilestoneService

--!strict
--[[
	PlaytimeService — odměny za odehraný čas.

	Tohle je ta druhá polovina grindu: peníze nejdou jen z klikání,
	ale i z toho, že hráč ve hře prostě je. Odměna se sama nezvedne —
	hráč si ji musí vyzvednout, což ho vrátí do hry.

	Vyzvednuté milníky se pamatují napříč sessionami (ClaimedRewards),
	takže restart serveru grind neresetuje.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)

local ASMRService = require(script.Parent.ASMRService)
local DataService = require(script.Parent.DataService)

local PlaytimeService = {}

local function rewardKey(minutes: number): string
	return tostring(minutes)
end

-- Seznam odměn s jejich stavem (pro UI)
function PlaytimeService.snapshot(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return {}
	end

	local playtime = DataService.playtime(player)
	local list = {}

	for _, reward in Config.Playtime do
		local required = reward.Minutes * 60
		table.insert(list, {
			Minutes = reward.Minutes,
			Label = reward.Label,
			Coins = reward.Coins,
			Claimed = profile.ClaimedRewards[rewardKey(reward.Minutes)] == true,
			Ready = playtime >= required,
			Remaining = math.max(required - playtime, 0),
		})
	end

	return list
end

function PlaytimeService.claim(player: Player, minutes: number)
	local profile = DataService.get(player)
	if not profile or typeof(minutes) ~= "number" then
		return
	end

	local reward
	for _, entry in Config.Playtime do
		if entry.Minutes == minutes then
			reward = entry
			break
		end
	end

	if not reward then
		return
	end

	local key = rewardKey(minutes)
	if profile.ClaimedRewards[key] then
		return
	end

	if DataService.playtime(player) < reward.Minutes * 60 then
		Remotes.Notify:FireClient(player, { Text = "Tuhle odměnu ještě nemáš odehranou.", Kind = "warn" })
		return
	end

	-- Odměna za čas roste s rebirthy stejně jako výdělky z krájení
	local payout = math.floor(reward.Coins * Economy.rebirthMultiplier(profile))

	profile.ClaimedRewards[key] = true
	profile.Coins += payout
	DataService.markDirty(player)
	DataService.save(player)

	ASMRService.pushProfile(player)
	Remotes.Notify:FireClient(player, {
		Text = `Odměna za {reward.Label}: +{Format.short(payout)} 💰`,
		Kind = "success",
	})
end

-- Pošle hráči aktuální stav odměn (při vstupu i v pravidelné smyčce)
function PlaytimeService.push(player: Player)
	if DataService.get(player) then
		Remotes.RewardReady:FireClient(player, PlaytimeService.snapshot(player))
	end
end

function PlaytimeService.start()
	Remotes.ClaimReward.OnServerEvent:Connect(function(player, minutes)
		PlaytimeService.claim(player, minutes)
	end)

	-- Hlídá, kdy hráči nová odměna dozraje, a dá mu vědět
	task.spawn(function()
		while true do
			task.wait(10)

			for _, player in Players:GetPlayers() do
				PlaytimeService.push(player)
			end
		end
	end)
end

return PlaytimeService

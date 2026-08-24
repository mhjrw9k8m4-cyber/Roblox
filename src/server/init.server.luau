--!strict
--[[
	Server — startovní bod.

	Nejdřív se postaví světy, pak se nastartují služby a teprve potom se
	napojí hráči. Kdo se připojil během startu, se dopracuje smyčkou na konci.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local Services = script:WaitForChild("Services")
local Analytics = require(Services.AnalyticsService)
local DataService = require(Services.DataService)
local EventService = require(Services.EventService)
local GameService = require(Services.GameService)
local Guard = require(Services.GuardService)
local LeaderboardService = require(Services.LeaderboardService)
local MonetizationService = require(Services.MonetizationService)
local PetService = require(Services.PetService)
local PlayerService = require(Services.PlayerService)
local RetentionService = require(Services.RetentionService)
local ShopService = require(Services.ShopService)
local TradeService = require(Services.TradeService)
local WorldService = require(Services.WorldService)

local function onCharacterAdded(player: Player)
	local character = player.Character
	if not character then
		return
	end

	character:WaitForChild("Humanoid")
	-- Chvilka, ať se postava stihne poskládat, než s ní hneme
	task.wait(0.15)

	GameService.teleport(player)
	GameService.applyCharacter(player)
	PlayerService.applyCollisionGroup(character)
	PlayerService.refreshNameplate(player)
end

local function onPlayerAdded(player: Player)
	local profile = DataService.load(player)

	PlayerService.setupStats(player)
	PlayerService.grantOffline(player)
	RetentionService.ensureQuests(player)
	Analytics.markNew(player)
	Analytics.onboarding(player, "Joined")
	Analytics.world(player, profile.WorldIndex, false)
	GameService.pushProfile(player)
	RetentionService.push(player)

	-- Vlastnictví gamepassů je síťové volání, ať nedrží zbytek startu
	task.spawn(MonetizationService.refreshPasses, player)
	MonetizationService.pushOffers(player)
	task.spawn(MonetizationService.checkBadges, player)

	if not profile._canSave then
		Remotes.Notify:FireClient(player, {
			Text = profile._lockReason
				or "Saving is off (DataStore unavailable) — progress will not be kept.",
			Kind = "warn",
		})
	end

	player.CharacterAdded:Connect(function()
		task.spawn(onCharacterAdded, player)
	end)

	if player.Character then
		task.spawn(onCharacterAdded, player)
	end
end

-- Start ---------------------------------------------------------------------

WorldService.build()

DataService.start()
Guard.start()
GameService.start()
ShopService.start()
PetService.start()
RetentionService.start()
MonetizationService.start()
LeaderboardService.start()
EventService.start()
TradeService.start()
Analytics.start()
PlayerService.start()

Players.PlayerAdded:Connect(function(player)
	task.spawn(onPlayerAdded, player)
end)

for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

print(`[{Config.GameName}] Server běží — {#Config.Worlds} světů postaveno.`)
